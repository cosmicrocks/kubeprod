
local kube = import "../lib/kube.libsonnet";
local EXTERNAL_DNS_IMAGE = (import "images.json")["external-dns"];

{
  p:: "",
  metadata:: {
    metadata+: {
      namespace: "kubeprod",
    },
  },

  clusterRole: kube.ClusterRole($.p + "external-dns") {
    rules: [
      {
        apiGroups: [""],
        resources: ["services"],
        verbs: ["get", "watch", "list"],
      },
      {
        apiGroups: [""],
        resources: ["pods"],
        verbs: ["get","watch","list"],
      },
      {
        apiGroups: ["extensions"],
        resources: ["ingresses"],
        verbs: ["get", "watch", "list"],
      },
      {
        apiGroups: [""],
        resources: ["nodes"],
        verbs: ["get","watch","list"],
      },
    ],
  },

  clusterRoleBinding: kube.ClusterRoleBinding($.p + "external-dns-viewer") {
    roleRef_: $.clusterRole,
    subjects_+: [$.sa],
  },

  sa: kube.ServiceAccount($.p + "external-dns") + $.metadata {
  },

  deploy: kube.Deployment($.p + "external-dns") + $.metadata {
    local this = self,
    ownerId:: error "ownerId is required",
    spec+: {
      template+: {
        metadata+: {
          annotations+: {
            "prometheus.io/scrape": "true",
            "prometheus.io/port": "7979",
            "prometheus.io/path": "/metrics",
          },
        },
        spec+: {
          serviceAccountName: $.sa.metadata.name,
          containers_+: {
            edns: kube.Container("external-dns") {
              image: EXTERNAL_DNS_IMAGE,
              args_+: {
                sources_:: ["service", "ingress"],
                registry: "txt",
                "txt-prefix": "_externaldns.",
                "txt-owner-id": this.ownerId,
                "domain-filter": this.ownerId,
              },
              args+: ["--source=%s" % s for s in self.args_.sources_],
              ports_+: {
                metrics: {containerPort: 7979},
              },
              readinessProbe: {
                httpGet: {path: "/healthz", port: "metrics"},
              },
              livenessProbe: self.readinessProbe,
            },
          },
        },
      },
    },
  },
}
