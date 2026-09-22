using '../main.bicep'

param environment = 'shared'
param location = 'eastus2'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'shared01')
param containerRegistryName = 'acrmrdshared'
param allowedLocations = ['eastus2', 'centralus']
// The environment, agent identity, ACR pull and kv-mrd-shared-<uniqueSuffix> vault deploy
// regardless. Flip this to true once the owner has stored the azdo-agent-pat secret in that
// vault (see main.bicep output agentPoolPatSecretUri) — until then the two caj-mrd-shared-agent*
// Container Apps jobs stay undeployed.
param agentPoolEnabled = false
// Subscription owner's AAD object id. An RBAC-authorized vault grants Owner no data actions, so
// this is what lets the owner run `az keyvault secret set` for azdo-agent-pat.
// This is a public Entra object id used only for a role assignment, not a credential; it is
// allowlisted for the Gitleaks generic-api-key rule in platform-infrastructure/.gitleaks.toml.
param secretsOfficerPrincipalId = '25ca776b-197d-4d33-be4c-7f71d4aafced'
