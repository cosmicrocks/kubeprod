// Top-level file for AWS

local cert_manager = import '../components/cert-manager.jsonnet';
local elasticsearch = import '../components/elasticsearch.jsonnet';
local edns = import '../components/externaldns.jsonnet';
local fluentd_es = import '../components/fluentd-es.jsonnet';
local kibana = import '../components/kibana.jsonnet';
local nginx_ingress = import '../components/nginx-ingress.jsonnet';
local oauth2_proxy = import '../components/oauth2-proxy.jsonnet';
local kube = import '../lib/kube.libsonnet';

local kp =
  {
    config+:: {
      dnsZone: 'cosmic.rocks',
      stage: 'staging',
      contactEmail: 'itamar@cosmic.rocks',
      externalDns: {
        external_dns_zone_name: 'cosmic.rocks',
      },
      oauthProxy: {
        authz_domain: 'cosmic.rocks',
        google_groups: '',
        google_admin_email: 'itamar@cosmic.rocks',
        client_id: '',
        client_secret: '',
        cookie_secret: '',
      },
    },

    // Shared metadata for all components
    namespace: kube.Namespace('kubeprod'),

    external_dns_zone_name:: $.config.dnsZone,
    letsencrypt_contact_email:: $.config.contactEmail,
    letsencrypt_environment:: 'prod',

    edns: edns {
      deploy+: {
        ownerId: $.external_dns_zone_name,
        spec+: {
          template+: {
            spec+: {
              containers_+: {
                edns+: {
                  args_+: {
                    provider: 'aws',
                  },
                },
              },
            },
          },
        },
      },
    },

    cert_manager: cert_manager {
      letsencrypt_contact_email:: $.letsencrypt_contact_email,
      letsencrypt_environment:: $.letsencrypt_environment,

      letsencryptProdDns+: cert_manager.ClusterIssuer('letsencrypt-prod-dns') {
        local this = self,
        spec+: {
          acme+: {
            server: 'https://acme-v02.api.letsencrypt.org/directory',
            email: $.letsencrypt_contact_email,
            privateKeySecretRef: { name: this.metadata.name },
            dns01: {
              providers: [
                {
                  name: 'letsencrypt-prod-dns',
                  route53: {
                    region: 'us-east-1',
                  },
                },
              ],
            },
          },
        },
      },
    },

    nginx_ingress: nginx_ingress {
      svc+: {
        metadata+: {
          annotations+: {
            'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb',
          },
        },
      },

      config+: {
        data+: {
          'proxy-protocol': 'True',
          'real-ip-header': 'proxy_protocol',
        },
      },

      hpa+: {
        spec+: {
          targetCPUUtilizationPercentage: 50,
        },
      },

      controller+: {
        spec+: {
          template+: {
            spec+: {
              affinity+: {
                podAntiAffinity: {
                  preferredDuringSchedulingIgnoredDuringExecution: [
                    {
                      weight: 50,
                      podAffinityTerm: {
                        labelSelector: { matchLabels: { name: 'nginx-ingress-controller' } },
                        topologyKey: 'failure-domain.beta.kubernetes.io/zone',
                      },
                    },
                    {
                      weight: 100,
                      podAffinityTerm: {
                        labelSelector: { matchLabels: { name: 'nginx-ingress-controller' } },
                        topologyKey: 'kubernetes.io/hostname',
                      },
                    },
                  ],
                },
              },
              containers_+: {
                default+: {
                  resources: {
                    requests: { cpu: '4', memory: '4Gi' },
                    limits: { cpu: '6', memory: '6Gi' },
                  },
                },
              },
            },
          },
        },
      },
    },

    oauth2_proxy: oauth2_proxy {
      local oauth2 = self,

      secret+: {
        data_+: $.config.oauthProxy,
      },

      ingress+: {
        host: "auth." + $.config.externalDns.external_dns_zone_name,
      },

      deploy+: {
        spec+: {
          template+: {
            spec+: {
              containers_+: {
                proxy+: {
                  image: 'docker.io/colemickens/oauth2_proxy:latest',
                  args_+: {
                   'email-domain': $.config.dnsZone,
                    provider: 'google',
                    google_groups_:: $.config.oauthProxy.google_groups,
                  },
                  args+: ['--google-group=' + g for g in std.set(self.args_.google_groups_)],
                },
              },
            },
          },
        },
      },
    },

    fluentd_es: fluentd_es {
      daemonset+: {
        spec+: {
          template+: {
            spec+: {
              tolerations: [
                {
                  key: 'node-role.kubernetes.io/system',
                  operator: 'Exists',
                  effect: 'NoSchedule',
                },
              ],
            },
          },
        },
      },
      es:: $.elasticsearch,
    },

    elasticsearch: elasticsearch {
      sts+: {
        spec+: {
          template+: {
            spec+: {
              containers_+: {
                elasticsearch_logging+: {
                  image: 'bitnami/elasticsearch:6.6.0',
                  resources: {
                    requests: {
                      cpu: if $.config.stage == 'staging' then '2' else if $.config.stage == 'production' then '4',
                      memory: if $.config.stage == 'staging' then '8Gi' else if $.config.stage == 'production' then '32Gi',
                    },
                    limits: {
                      cpu: if $.config.stage == 'staging' then '4' else if $.config.stage == 'production' then '8',
                      memory: if $.config.stage == 'staging' then '16Gi' else if $.config.stage == 'production' then '64Gi',
                    },
                  },
                },
              },
              tolerations: [
                {
                  key: 'node-role.kubernetes.io/system',
                  operator: 'Exists',
                  effect: 'NoSchedule',
                },
              ],
            },
          },
          volumeClaimTemplates_+: {
            data: { storage: if $.config.stage == 'staging' then '1000Gi' else if $.config.stage == 'production' then '8000Gi' },
          },
        },
      },
    },

    kibana: kibana {
      deploy+: {
        spec+: {
          template+: {
            spec+: {
              containers_+: {
                kibana+: {
                  image: 'bitnami/kibana:6.6.0',
                },
              },
            },
          },
        },
      },
      es:: $.elasticsearch,

      ingress+: {
        host: 'kibana.' + $.external_dns_zone_name,
      },
    },

  };

{ ['namespace']: kp.namespace } +
{ ['cert-manager-' + name]: kp.cert_manager[name] for name in std.objectFields(kp.cert_manager) } +
{ ['external-dns-' + name]: kp.edns[name] for name in std.objectFields(kp.edns) } +
{ ['elasticsearch-' + name]: kp.elasticsearch[name] for name in std.objectFields(kp.elasticsearch) } +
{ ['fluent-es-' + name]: kp.fluentd_es[name] for name in std.objectFields(kp.fluentd_es) } +
{ ['kibana-' + name]: kp.kibana[name] for name in std.objectFields(kp.kibana) } +
{ ['nginx-ingress-' + name]: kp.nginx_ingress[name] for name in std.objectFields(kp.nginx_ingress) } +
{ ['oauth2-proxy-' + name]: kp.oauth2_proxy[name] for name in std.objectFields(kp.oauth2_proxy) }
