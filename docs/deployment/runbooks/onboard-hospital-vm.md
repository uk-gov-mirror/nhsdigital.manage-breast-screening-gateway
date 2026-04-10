# Hospital VM Onboarding Runbook

> **Script**: `scripts/powershell/arc-setup.ps1`
> **When to use**: Onboarding a new NHS hospital gateway VM to Azure Arc for the first time

---

## Prerequisites

- [ ] Hospital IT has provisioned the gateway VM (Windows Server 2022 or later)
- [ ] VM has outbound internet access to:
  - `*.arc.azure.com`
  - `*.his.arc.azure.com`
  - `relay-manbrs-<env>.servicebus.windows.net`
- [ ] Trust ODS code confirmed via the [ODS portal](https://odsportal.nhsbsa.nhs.uk/)
- [ ] PACS vendor confirmed (`sectra` | `fujifilm` | `agfa` | `philips` | `carestream`)
- [ ] NHS region confirmed (`nw` | `neyh` | `mids` | `eoe` | `lon` | `se` | `sw`)
- [ ] Deployment ring agreed with the programme team
- [ ] `arc-onboarding-spn-client-id` and `arc-onboarding-spn-client-secret` retrieved from Key Vault

---

## Step 1 — Determine site parameters

| Parameter | Format | Example |
|-----------|--------|---------|
| `SiteCode` | `gw-<ODSCode>-<instance>` | `gw-RVJ-01` |
| `SiteName` | Trust name, hyphen-separated, no spaces | `North-Bristol-NHS-Trust` |
| `NHSRegion` | One of: `nw` `neyh` `mids` `eoe` `lon` `se` `sw` | `sw` |
| `PacsVendor` | One of: `sectra` `fujifilm` `agfa` `philips` `carestream` | `sectra` |
| `SiteType` | `static` or `mobile` | `static` |
| `DeploymentRing` | `ring1`–`ring4` (see below) | `ring1` |

**Ring assignments:**

| Ring | Sites |
|------|-------|
| ring0 | Test VM only (`mbsgw-review`) |
| ring1 | 1 site per PACS vendor (first real sites) |
| ring2 | 1 site per NHS region |
| ring3 | Remaining static sites |
| ring4 | Mobile units |

## Step 2 — Run Arc onboarding script on the gateway VM

Copy `scripts/powershell/arc-setup.ps1` to the VM and run from an **elevated PowerShell session**:

```powershell
.\arc-setup.ps1 `
    -SubscriptionId         "<spoke-subscription-id>" `
    -TenantId               "<tenant-id>" `
    -ResourceGroup          "rg-manbgw-<env>-uks-arc-enabled-servers" `
    -Location               "uksouth" `
    -ServicePrincipalId     "<arc-onboarding-spn-client-id>" `
    -ServicePrincipalSecret "<arc-onboarding-spn-client-secret>" `
    -SiteCode               "gw-RVJ-01" `
    -SiteName               "North-Bristol-NHS-Trust" `
    -NHSRegion              "sw" `
    -PacsVendor             "sectra" `
    -SiteType               "static" `
    -DeploymentRing         "ring1"
```

The script will:
1. Install the Azure Arc agent (`azcmagent`) if not already present
2. Stamp site metadata as tags on the Arc machine resource
3. Connect the VM to Azure Arc with `--resource-name` set to `SiteCode`

Logs are written to `C:\ArcSetup\ArcSetup.log`.

**Verify**: In the Azure portal, navigate to `rg-manbgw-<env>-uks-arc-enabled-servers` → Azure Arc machines → `gw-RVJ-01`. Status should be **Connected**.

## Step 3 — Trigger Terraform to provision the Hybrid Connection

Run the ADO pipeline **Deploy Arc Infrastructure - \<env\>** manually. Terraform discovers the new Arc machine and creates:

- `hc-gw-RVJ-01` in the relay namespace (`relay-manbrs-<env>`)
- `listen` auth rule on that Hybrid Connection

**Verify**: In the Azure portal, navigate to `relay-manbrs-<env>` → Hybrid Connections → `hc-gw-RVJ-01` is present.

## Step 4 — Deploy the gateway application

Run the ADO pipeline **Deploy Gateway - \<env\>** with:

```
targetSiteCode : gw-RVJ-01
releaseTag     : latest        (or a specific tag, e.g. v1.2.3)
```

The pipeline:
1. Retrieves the listen SAS key for `hc-gw-RVJ-01`
2. Sends an Arc Run Command to `gw-RVJ-01` that writes `.env` and runs `deploy.ps1`
3. Polls for completion and reports success or failure

## Step 5 — Smoke test

Run from the gateway VM or via Arc Run Command:

```powershell
Get-Service Gateway-PACS, Gateway-MWL, Gateway-Upload, Gateway-Relay | Select-Object Name, Status
```

Expected: all four services **Running**.

Check Log Analytics Workspace for an initial heartbeat within 5 minutes of service start.

---

## Parameters reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-SubscriptionId` | Yes | — | Azure spoke subscription ID |
| `-TenantId` | Yes | — | Azure Entra tenant ID |
| `-ResourceGroup` | Yes | — | Arc-enabled servers resource group |
| `-Location` | Yes | — | Azure region (always `uksouth`) |
| `-ServicePrincipalId` | Yes | — | Arc onboarding SPN client ID |
| `-ServicePrincipalSecret` | Yes | — | Arc onboarding SPN client secret |
| `-SiteCode` | No | *(hostname)* | Arc resource name and tag; format `gw-<ODSCode>-<instance>` |
| `-SiteName` | No | *(not set)* | Human-readable trust name; no spaces |
| `-NHSRegion` | No | *(not set)* | NHS region code |
| `-PacsVendor` | No | *(not set)* | PACS system vendor |
| `-SiteType` | No | `static` | `static` or `mobile` |
| `-DeploymentRing` | No | `ring0` | Rollout ring (`ring0`–`ring4`) |

---

## Troubleshooting

### Arc agent fails to connect

Check `C:\ArcSetup\ArcSetup.log` on the VM. Common causes:

- **Firewall blocking outbound** — confirm the VM can reach `*.arc.azure.com` on port 443
- **SPN credentials wrong** — verify client ID and secret from Key Vault are current
- **VM already registered** — if the machine was previously connected under a different name, disconnect first: `azcmagent disconnect`

### Arc machine shows as Disconnected after onboarding

The agent may have lost connectivity. Check:

```powershell
azcmagent show
```

If disconnected, re-run the script. It is safe to re-run — the agent will reconnect and update tags.

### Hybrid Connection not created after Terraform run

The Arc machine must appear in the resource group before Terraform can create the HC. Confirm the machine is **Connected** in the portal (Step 2 verify), then re-run the pipeline.

### Gateway services not starting after deploy

Check the deployment log on the VM:

```powershell
Get-ChildItem "C:\Program Files\NHS\ManageBreastScreeningGateway\logs\deployments\deploy-*" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
    ForEach-Object { Get-Content $_.FullName }
```
