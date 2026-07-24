# Advanced Ansible Network Automation Workshop

A hands-on workshop for automating multi-vendor **EVPN VXLAN spine-leaf fabrics** using **Red Hat Ansible Automation Platform**. Participants work through progressive modules covering dynamic inventory with NetBox, configuration management via Git, network compliance, automated deployment of base/underlay/overlay configurations, performance tuning, and configuration drift detection.

The lab environment runs Arista EOS and Cisco NX-OS virtual switches on [Containerlab](https://containerlab.dev/), managed through AAP workflows with NetBox as the source of truth and Gitea as the Git backend.

Designed for [Red Hat Demo Platform (RHDP)](https://demo.redhat.com) with the Showroom UI.

## Workshop Modules

| Module | Topic |
|--------|-------|
| 1-1 | Dynamic Inventory (NetBox + AAP) |
| 1-2 | Backups as Code |
| 1-3 | Network Compliance |
| 1-4 | Base Configs |
| 1-5 | Underlay Configs |
| 1-6 | Overlay Configs |
| 1-7 | Tuning for Scale |
| 1-8 | Configuration Drift Restore |

## Lab Environment

- **Containerlab host** with `ansible-navigator`, VS Code, and a pre-built execution environment
- **Six network devices**: Arista EOS (spine1, spine2, leaf1, leaf2) and Cisco NX-OS (leaf3, leaf4)
- **Ansible Automation Platform** for workflow-driven automation
- **NetBox** as the dynamic inventory source
- **Gitea** as the Git repository for network configurations

## Directory Structure

```
.
├── content/                    # Antora documentation (workshop guide)
│   ├── antora.yml
│   └── modules/ROOT/pages/
├── aap_configuration_export/   # AAP configuration as code
├── config/                     # RHDP VM, network, and firewall definitions
├── lab-automation/             # Ansible playbooks for lab deployment
├── netbox-docker/              # NetBox container configuration
├── network-workshop/           # Ansible playbooks used during the workshop
├── runtime-automation/         # Per-module setup/solve/validation scripts
├── setup-automation/           # First-boot provisioning scripts
├── site.yml                    # Antora site config
└── ui-config.yml               # Showroom tab and module definitions
```

## Development

1. Edit content in `content/modules/ROOT/pages/`
2. Preview locally with Antora: `npx antora site.yml`
3. Push to `main` -- RHDP deployments pull from head of `main`

## License

[MIT](LICENSE)
