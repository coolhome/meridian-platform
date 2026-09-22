// Self-hosted Azure Pipelines agents as Container Apps jobs, pool "meridian-agents" (shared tier
// only). Gated by the caller: agentPoolEnabled stays false in shared.bicepparam until the owner
// has stored the azdo-agent-pat secret in the vault this deployment also creates.
//
// caj-<prefix>-<environment>-agent: Event-triggered, scales 0->1 on the KEDA azure-pipelines
// scaler polling the pool queue. caj-<prefix>-<environment>-agent-placeholder: Manual-triggered;
// run once by tooling so an offline agent stays registered in the pool (a pool with zero
// registered agents fails queued jobs with "no agent found" before the event-driven job ever gets
// a chance to scale out).
param location string
param tags object
param prefix string
param environment string
param environmentId string
param registryServer string
param identityResourceId string
param keyVaultSecretUri string
param agentImage string

var jobNamePrefix = 'caj-${prefix}-${environment}'

var registries = [
  {
    server: registryServer
    identity: identityResourceId
  }
]
// azdo-org-url is a plain value (not a secret in any real sense) because the KEDA azure-pipelines
// scaler's auth block only accepts secretRef, not inline metadata, for organizationURL — see the
// scale rule below. azdo-agent-pat stays Key Vault-backed.
var secrets = [
  {
    name: 'azdo-agent-pat'
    keyVaultUrl: keyVaultSecretUri
    identity: identityResourceId
  }
  {
    name: 'azdo-org-url'
    value: 'https://dev.azure.com/coolhome'
  }
]
var baseEnv = [
  { name: 'AZP_URL', value: 'https://dev.azure.com/coolhome' }
  { name: 'AZP_POOL', value: 'meridian-agents' }
  { name: 'AZP_TOKEN', secretRef: 'azdo-agent-pat' }
]

resource agentJob 'Microsoft.App/jobs@2025-01-01' = {
  name: '${jobNamePrefix}-agent'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      triggerType: 'Event'
      replicaTimeout: 5400
      replicaRetryLimit: 0
      registries: registries
      secrets: secrets
      eventTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
        scale: {
          minExecutions: 0
          maxExecutions: 1
          pollingInterval: 30
          rules: [
            {
              // Shape matches the Container Apps jobs "self-hosted CI/CD runners" tutorial:
              // organizationURL and personalAccessToken come from auth (secretRef), not metadata,
              // so the PAT and org URL never appear in the job definition in plaintext.
              name: 'azure-pipelines'
              type: 'azure-pipelines'
              metadata: {
                poolName: 'meridian-agents'
                targetPipelinesQueueLength: '1'
              }
              auth: [
                {
                  secretRef: 'azdo-agent-pat'
                  triggerParameter: 'personalAccessToken'
                }
                {
                  secretRef: 'azdo-org-url'
                  triggerParameter: 'organizationURL'
                }
              ]
            }
          ]
        }
      }
    }
    template: {
      containers: [
        {
          name: 'agent'
          image: agentImage
          resources: {
            cpu: json('2')
            memory: '4Gi'
          }
          env: baseEnv
        }
      ]
    }
  }
}

// Started once by tooling (az containerapp job start), not by an event: keeps one agent
// registered offline in "meridian-agents" so the pool is never empty. AZP_AGENT_NAME is fixed
// (not left to hostname, unlike the event-driven job) so re-running -RegisterPlaceholder replaces
// the same agent via start.sh's --replace instead of registering a new one each time.
resource agentPlaceholderJob 'Microsoft.App/jobs@2025-01-01' = {
  name: '${jobNamePrefix}-agent-placeholder'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 300
      replicaRetryLimit: 0
      registries: registries
      secrets: secrets
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
    }
    template: {
      containers: [
        {
          name: 'agent'
          image: agentImage
          resources: {
            cpu: json('2')
            memory: '4Gi'
          }
          env: concat(baseEnv, [
            { name: 'AZP_PLACEHOLDER', value: '1' }
            { name: 'AZP_AGENT_NAME', value: 'placeholder-agent' }
          ])
        }
      ]
    }
  }
}

output agentJobName string = agentJob.name
output agentPlaceholderJobName string = agentPlaceholderJob.name
