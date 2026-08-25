"""Kube CRUD handler for a private EKS cluster.

WARNING: This code was generated with AI assistance and should be reviewed
before use in production environments.

Runs inside the VPC with kubectl and helm bundled in the deployment package.
No internet access required.

Supports full CRUD lifecycle via aws_lambda_invocation lifecycle_scope = "CRUD":
  - create/update: apply manifests or helm upgrade --install
  - delete: remove manifests or helm uninstall

Event payload:
  {"type": "manifest", "name": "...", "manifest": "<yaml>"}
  {"type": "helm", "name": "...", "release": "...", "chart": "...",
   "chart_files": {"Chart.yaml": "...", "templates/x.yaml": "..."},
   "repository": "https://...", "version": "x.y.z", "namespace": "...",
   "create_namespace": true, "values": "<yaml>"}
"""

import base64
import json
import os
import subprocess
import tempfile

import boto3
from botocore.signers import RequestSigner

CLUSTER_NAME = os.environ["CLUSTER_NAME"]
REGION = os.environ.get("AWS_REGION", "")
TOKEN_TTL = 60

KUBECTL_PATH = "/var/task/bin/kubectl"
HELM_PATH = "/var/task/bin/helm"


def _ensure_binaries():
    if not os.path.isfile(KUBECTL_PATH):
        raise RuntimeError(f"kubectl not found at {KUBECTL_PATH}")
    if not os.path.isfile(HELM_PATH):
        raise RuntimeError(f"helm not found at {HELM_PATH}")


def _bearer_token():
    session = boto3.session.Session()
    client = session.client("sts", region_name=REGION)
    signer = RequestSigner(
        client.meta.service_model.service_id,
        REGION,
        "sts",
        "v4",
        session.get_credentials(),
        session.events,
    )
    signed_url = signer.generate_presigned_url(
        {
            "method": "GET",
            "url": f"https://sts.{REGION}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15",
            "body": {},
            "headers": {"x-k8s-aws-id": CLUSTER_NAME},
            "context": {},
        },
        region_name=REGION,
        expires_in=TOKEN_TTL,
        operation_name="",
    )
    return "k8s-aws-v1." + base64.urlsafe_b64encode(signed_url.encode()).decode().rstrip("=")


def _write_kubeconfig():
    cluster = boto3.client("eks", region_name=REGION).describe_cluster(name=CLUSTER_NAME)["cluster"]
    ca_path = "/tmp/ca.crt"
    with open(ca_path, "wb") as f:
        f.write(base64.b64decode(cluster["certificateAuthority"]["data"]))

    kubeconfig = {
        "apiVersion": "v1",
        "kind": "Config",
        "clusters": [
            {
                "name": CLUSTER_NAME,
                "cluster": {"server": cluster["endpoint"], "certificate-authority": ca_path},
            }
        ],
        "users": [{"name": CLUSTER_NAME, "user": {"token": _bearer_token()}}],
        "contexts": [
            {"name": CLUSTER_NAME, "context": {"cluster": CLUSTER_NAME, "user": CLUSTER_NAME}}
        ],
        "current-context": CLUSTER_NAME,
    }
    path = "/tmp/kubeconfig"
    with open(path, "w") as f:
        json.dump(kubeconfig, f)
    return path


def _run(cmd, env):
    print("+ " + " ".join(cmd))
    result = subprocess.run(cmd, env=env, capture_output=True, text=True)
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr)
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(cmd)}\n{result.stderr}")
    return result.stdout


def _helm_env(base):
    env = dict(base)
    env.update(
        {
            "HOME": "/tmp",
            "HELM_CACHE_HOME": "/tmp/.helm/cache",
            "HELM_CONFIG_HOME": "/tmp/.helm/config",
            "HELM_DATA_HOME": "/tmp/.helm/data",
        }
    )
    for d in ("cache", "config", "data"):
        os.makedirs(f"/tmp/.helm/{d}", exist_ok=True)
    return env


def _handle_apply(event):
    kubeconfig = _write_kubeconfig()
    env = dict(os.environ, KUBECONFIG=kubeconfig)
    kind = event["type"]

    if kind == "manifest":
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False, dir="/tmp") as f:
            f.write(event["manifest"])
            manifest_path = f.name
        _run([KUBECTL_PATH, "apply", "--server-side", "--force-conflicts", "-f", manifest_path], env)
        return {"status": "applied", "name": event.get("name")}

    if kind == "helm":
        env = _helm_env(env)
        repo = event.get("repository")
        chart = event["chart"]
        chart_files = event.get("chart_files")

        if chart_files:
            chart_dir = f"/tmp/charts/{event.get('name', 'chart')}"
            for filepath, content in chart_files.items():
                full_path = os.path.join(chart_dir, filepath)
                os.makedirs(os.path.dirname(full_path), exist_ok=True)
                with open(full_path, "w") as f:
                    f.write(content)
            chart = chart_dir
        elif repo and repo.startswith("http"):
            _run([HELM_PATH, "repo", "add", event["release"], repo], env)
            _run([HELM_PATH, "repo", "update"], env)
            chart = f"{event['release']}/{chart}"
        elif repo and repo.startswith("oci://"):
            chart = f"{repo}/{chart}"

        cmd = [
            HELM_PATH, "upgrade", "--install", event["release"], chart,
            "--namespace", event["namespace"],
            "--wait", "--timeout", "10m",
        ]
        if event.get("create_namespace", True):
            cmd.append("--create-namespace")
        if event.get("version"):
            cmd += ["--version", event["version"]]
        if event.get("values"):
            with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False, dir="/tmp") as f:
                f.write(event["values"])
                cmd += ["-f", f.name]
        _run(cmd, env)
        return {"status": "released", "name": event.get("name")}

    raise ValueError(f"unknown payload type: {kind}")


def _handle_delete(event):
    kubeconfig = _write_kubeconfig()
    env = dict(os.environ, KUBECONFIG=kubeconfig)
    kind = event["type"]

    if kind == "manifest":
        with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False, dir="/tmp") as f:
            f.write(event["manifest"])
            manifest_path = f.name
        _run([KUBECTL_PATH, "delete", "--ignore-not-found", "-f", manifest_path], env)
        return {"status": "deleted", "name": event.get("name")}

    if kind == "helm":
        env = _helm_env(env)
        cmd = [HELM_PATH, "uninstall", event["release"], "--namespace", event["namespace"]]
        try:
            _run(cmd, env)
        except RuntimeError as e:
            if "not found" in str(e):
                return {"status": "already_removed", "name": event.get("name")}
            raise
        return {"status": "uninstalled", "name": event.get("name")}

    raise ValueError(f"unknown payload type for delete: {kind}")


def handler(event, _context):
    _ensure_binaries()

    tf_meta = event.get("tf")
    if tf_meta:
        action = tf_meta.get("action")
        if action == "delete":
            return _handle_delete(event)
        return _handle_apply(event)

    return _handle_apply(event)
