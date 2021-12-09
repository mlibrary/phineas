{
  _config+:: {
    prometheus: {
      name: "my-app",
      githubTeams: [],
      dexClient: "",
      dexSecret: "",
      dexUrl: "",

      prometheusServer: {
        name: "prometheus-server",
        image: "prom/prometheus:v2.31.1",
        reloadImage: "jimmidyson/configmap-reload:v0.5.0",
        namespaces: [],
        storage: "2Gi",
        storageClass: "rook-ceph-block",
        scrape_interval: "10s",
        scrape_configs: [],
        alerting_rules: {},
        recording_rules: {},
        alerting_rules_file: std.manifestYamlDoc(self.alerting_rules),
        recording_rules_file: std.manifestYamlDoc(self.recording_rules),
        alertmanagers: [],
      },

      pushgateway: {
        enabled: false,
        name: "pushgateway",
        image: "prom/pushgateway:v1.4.2",
      },

      grafana: {
        host: "",
        name: "grafana",
        image: "grafana/grafana:8.2.6",
        cpuLimit: "500m",
        memoryLimit: "128Mi",
        storage: "128Mi",
        storageClass: "rook-ceph-block",
        clusterIssuer: "letsencrypt-prod",
      },
    }
  }
}
