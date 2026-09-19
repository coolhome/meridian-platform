# Security

<!-- Stamped from governance/templates/overlay. -->

* Report vulnerabilities to the Security Champions group in Azure DevOps, not in a work item.
* Secrets never live in this repository. Runtime secrets come from Key Vault through the
  service's managed identity; pipeline secrets come from Key Vault-linked variable groups.
* Every pipeline in this repository `extends` a template from `meridian-pipeline-templates`.
  Environment checks reject anything else.
* Dependencies are locked (`packages.lock.json` / `package-lock.json`) and restored in locked
  mode in CI.
