# Deployment

PostgRESTxn ships as an OCI image. Reference the image URL in your deployment config and provide the required env vars - see [Configuration](configuration.md).

## Image

| Registry | URL |
|---|---|
| GitHub Container Registry | `ghcr.io/snehil-shah/postgrestxn:<tag>` |
| Docker Hub | `docker.io/snehilshah/postgrestxn:<tag>` |

!!! tip
    Use a tagged version (e.g., `:v0.1.0`) in production, not `:latest`.

## Ports

- `4000` (default `HTTP_PORT`) - main API
- `9568` (default `ADMIN_HTTP_PORT`) - admin endpoints. Restrict to your monitoring network, do not expose publicly

## Kubernetes example

A minimal Deployment + Service example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgrestxn
spec:
  replicas: 2
  selector:
    matchLabels: {app: postgrestxn}
  template:
    metadata:
      labels: {app: postgrestxn}
    spec:
      containers:
        - name: postgrestxn
          image: ghcr.io/snehil-shah/postgrestxn:v0.1.0
          ports:
            - {name: api, containerPort: 4000}
            - {name: admin, containerPort: 9568}
          env:
            - name: DATABASE_URL
              valueFrom: {secretKeyRef: {name: postgrestxn-db, key: url}}
            - name: ANON_ROLE
              value: web_anon
          livenessProbe:
            httpGet: {path: /live, port: admin}
          readinessProbe:
            httpGet: {path: /ready, port: admin}
---
apiVersion: v1
kind: Service
metadata:
  name: postgrestxn
spec:
  selector: {app: postgrestxn}
  ports:
    - {name: api, port: 4000}
    - {name: admin, port: 9568}
```

The `admin` port stays on the cluster-internal Service, don't include it in your public ingress.
