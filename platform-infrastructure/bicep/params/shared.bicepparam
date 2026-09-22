using '../main.bicep'

param environment = 'shared'
param location = 'eastus2'
param uniqueSuffix = readEnvironmentVariable('MERIDIAN_UNIQUE_SUFFIX', 'shared01')
param containerRegistryName = 'acrmrdshared'
param allowedLocations = ['eastus2', 'centralus']
// The environment, agent identity, ACR pull and kv-mrd-shared-<uniqueSuffix> vault deploy
// regardless. The azdo-agent-pat secret must already exist in kv-mrd-shared-ch2609 before this
// deploys true: a Key Vault secret reference on a Container Apps job is validated at creation,
// so the deployment fails if the secret is missing. Once the owner has stored that secret (see
// main.bicep output agentPoolPatSecretUri), flip this to true to deploy the two
// caj-mrd-shared-agent* Container Apps jobs; flip it back to false to remove them.
param agentPoolEnabled = true
// Subscription owner's AAD object id. An RBAC-authorized vault grants Owner no data actions, so
// this is what lets the owner run `az keyvault secret set` for azdo-agent-pat.
// This is a public Entra object id used only for a role assignment, not a credential; it is
// allowlisted for the Gitleaks generic-api-key rule in platform-infrastructure/.gitleaks.toml.
param secretsOfficerPrincipalId = '25ca776b-197d-4d33-be4c-7f71d4aafced'
