local tk = import 'tk';

{
  _config+:: {
    prometheusAdmin: {
      name: "some-team-prometheus",
      serviceAccountName: "prometheus-server",
      namespaces: [],
      clientCertSecretIsApplied: false,
    }
  }
} +
{
  local c = $._config.prometheusAdmin,

  prometheusAdmin+: {
    clusterrole: {
      apiVersion: "rbac.authorization.k8s.io/v1",
      kind: "ClusterRole",
      metadata: { name: "application-monitor-pods" },
      rules: [{
        apiGroups: [""],
        verbs: ["get", "list", "watch"],
        resources: ["pods"],
      }],
    },

    sa: {
      apiVersion: "v1",
      kind: "ServiceAccount",
      metadata: { name: c.serviceAccountName },
    },

    binding: [{
      apiVersion: "rbac.authorization.k8s.io/v1",
      kind: "RoleBinding",
      metadata: {
        name: c.name,
        namespace: namespace,
      },
      roleRef: {
        apiGroup: "rbac.authorization.k8s.io",
        kind: "ClusterRole",
        name: "application-monitor-pods",
      },
      subjects: [{
        kind: "ServiceAccount",
        name: c.serviceAccountName,
        namespace: tk.env.spec.namespace,
      }],
    } for namespace in c.namespaces],

    secret: if c.clientCertSecretIsApplied then {} else {
      apiVersion: "v1",
      kind: "Secret",
      type: "kubernetes.io/tls",
      metadata: { name: "prometheus-server" },
      data: {
        "tls.crt": std.base64(importstr "prometheus.crt"),
        "tls.key": std.base64(importstr "prometheus.key"),
        "ca.crt": std.base64(importstr "./ca.crt"),
      },
    },
  }
}
