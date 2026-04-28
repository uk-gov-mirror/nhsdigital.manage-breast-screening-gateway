# ADR-005: Use Managed Identity for Azure Relay authentication

Date: 2026-04-28

Status: Accepted

## Context

The gateway connects to Azure Relay Hybrid Connections to receive worklist actions from Manage Breast Screening. A connection must be authenticated to Azure Relay.

The initial implementation used Shared Access Signature (SAS) tokens. These are HMAC-SHA256 signatures computed from a shared secret key, embedded in the WebSocket connection URL as a query parameter (`sb-hc-token`). This required:

- A shared access key to be provisioned and stored as an environment variable (`AZURE_RELAY_SHARED_ACCESS_KEY`)
- The key name to be configured separately (`AZURE_RELAY_KEY_NAME`)
- Manual key rotation when keys needed to change

As the gateway runs inside the hospital network but is provisioned via Azure Arc, it can be assigned a managed identity through Arc-enabled infrastructure. Storing a long-lived shared secret in the environment is therefore unnecessary operational overhead and a potential security risk.

## Decision

We will use **Azure Managed Identity** to authenticate to Azure Relay, replacing SAS token generation.

At runtime, `DefaultAzureCredential` from the `azure-identity` SDK obtains a short-lived JWT from Azure AD, scoped to `https://relay.azure.com/.default`. This token is passed as an `Authorization: Bearer` HTTP header on the WebSocket upgrade request, which Azure Relay validates against Azure AD.

The `AZURE_RELAY_KEY_NAME` and `AZURE_RELAY_SHARED_ACCESS_KEY` environment variables are removed.

The gateway's managed identity must be assigned the **Azure Relay Listener** role on the hybrid connection resource in Azure.

`DefaultAzureCredential` is used (rather than `ManagedIdentityCredential` directly) so that the credential chain works in all environments: managed identity in Azure deployments, and Azure CLI credentials on developer machines.

## Consequences

### Positive Consequences

- **No secrets to manage:** No shared key to store, rotate, or accidentally leak
- **Fail-fast on misconfiguration:** A startup credential check raises `ClientAuthenticationError` immediately if the managed identity is not correctly configured, rather than failing silently in the reconnect loop
- **Consistent with platform direction:** Aligns with how the gateway already authenticates to the DICOM API (also via managed identity)

### Negative Consequences

- **Azure infrastructure dependency:** The managed identity and its role assignment must exist before the service can start; there is no fallback
