# Attacher une adresse IP publique à une machine virtuelle Azure : GUI, Azure CLI et Terraform

🌐 **Langues :** **Français** · [English](README.en.md) · [Deutsch](README.de.md)

## Contexte

Une entreprise migre une partie de son infrastructure vers Azure. La migration est découpée en petites tâches indépendantes pour limiter les risques et garder le contrôle. Cette tâche est l'une de ces étapes : **attacher une adresse IP publique existante à une machine virtuelle (VM) existante**, pour que la VM soit joignable depuis Internet (administration en SSH ou RDP, ou service public).

Dans ce README, les ressources s'appellent `my-vm` (la VM) et `my-public-ip` (l'IP publique). Remplace ces noms par les tiens.

La tâche est résolue de trois façons :

1. **Portail Azure (GUI)**
2. **Azure CLI**
3. **Terraform** (module, exécuté depuis ta propre machine, **sans** Azure CLI)

## Procédure générale : attacher une IP publique à une VM

Ces étapes valent pour n'importe quelle VM, quel que soit l'outil utilisé.

| Étape | Que faire | Pourquoi |
|---|---|---|
| 1. Comprendre la cible | Une IP publique n'est **pas** attachée à la VM elle-même, mais à la **configuration IP de la carte réseau (NIC) de la VM**, souvent nommée `ipconfig1` | La NIC est la prise réseau de la VM ; l'IP publique est l'adresse visible de l'extérieur branchée dessus |
| 2. Vérifier les prérequis | L'IP publique existe, est **libre** (associée à rien), se trouve dans la **même région** que la NIC et a la même version d'IP (IPv4) | Azure refuse une IP déjà utilisée ou située dans une autre région |
| 3. Trouver la NIC et sa configuration IP | Lister les NIC de la VM, puis les configurations IP de cette NIC | On associe l'IP à une configuration IP précise |
| 4. Associer l'IP | Portail, CLI ou Terraform : relier l'IP publique à la configuration IP | C'est l'attache proprement dite |
| 5. Vérifier | La VM affiche une IP publique, et l'IP publique affiche la configuration IP à laquelle elle est associée | Confirme que la VM possède bien l'IP |
| 6. Ouvrir les ports si besoin | Ajouter une règle de Network Security Group (NSG) pour SSH (22) ou RDP (3389) | Une IP publique Standard reste fermée tant qu'un NSG n'autorise pas le trafic |

À savoir :

- **Aucun arrêt de la VM n'est nécessaire.** Une IP publique s'associe pendant que la VM tourne. C'est différent de l'ajout d'une NIC à une VM, qui exige de la désallouer.
- Une configuration IP porte **une seule** IP publique. Une NIC peut avoir plusieurs configurations IP.
- Une IP **statique** garde son adresse. Une IP **dynamique** (Basic) ne reçoit son adresse qu'une fois allouée : elle peut donc n'afficher aucune adresse tant que la VM est désallouée.

## Concepts clés

| Concept | Exemple | Contre-exemple |
|---|---|---|
| Associer à la NIC | `my-public-ip` est reliée à `ipconfig1` de la NIC de la VM | Chercher un bouton « attacher à la VM » : il n'existe pas, tout se fait côté NIC |
| IP libre | `my-public-ip` n'est associée à aucune ressource | Une IP déjà associée à une autre NIC est refusée |
| Même région | IP publique et NIC dans la même région | Régions différentes : l'association est refusée |
| Associée ≠ joignable | La VM possède l'adresse publique | Les ports restent fermés tant qu'une règle NSG ne les autorise pas |
| Allocation statique | L'adresse ne change jamais : les enregistrements DNS restent valides | Une adresse dynamique peut changer, et le DNS pointe alors dans le vide |

Pourquoi garder l'IP publique comme ressource séparée ? Elle peut survivre à la VM : si la VM est détruite puis recréée, l'adresse (et les règles de pare-feu qui la référencent) reste identique.

## Prérequis

- Un abonnement Azure et un **groupe de ressources existant** contenant la VM et l'IP publique (note son nom).
- Pour Terraform : Terraform >= 1.5 sur ta machine (n'importe quel shell, par exemple Git Bash). Azure CLI **n'est pas** nécessaire.
- Pour Terraform : un **Service Principal** (client ID + client secret) avec le rôle *Contributor* sur le groupe de ressources, ainsi que le tenant ID et le subscription ID.

> Dans un shell, `<` et `>` sont des opérateurs de redirection. Ne colle jamais des emplacements comme `<RG>` tels quels : remplace-les par de vraies valeurs.

## Avant de commencer : vérifier la VM et l'IP publique

```bash
RG="mon-groupe-de-ressources"      # remplace par le nom de ton groupe de ressources

# La VM doit être provisionnée, sans IP publique pour l'instant
az vm show -d -g "$RG" -n my-vm \
  --query "{provisioning:provisioningState, power:powerState, ipPublique:publicIps}" -o table

# NIC de la VM et nom de sa configuration IP
NIC=$(az vm nic list -g "$RG" --vm-name my-vm --query "[0].id" -o tsv | awk -F/ '{print $NF}')
echo "NIC = $NIC"
az network nic ip-config list -g "$RG" --nic-name "$NIC" --query "[].{nom:name, primaire:primary}" -o table

# L'IP publique doit être libre : associeA doit valoir null
az network public-ip show -g "$RG" -n my-public-ip \
  --query "{ip:ipAddress, sku:sku.name, allocation:publicIPAllocationMethod, region:location, associeA:ipConfiguration.id}" -o json
```

Attendu : `Succeeded`, `VM running`, `ipPublique` vide, un nom de configuration IP (probablement `ipconfig1`), et `associeA` à `null`.

## Méthode 1 : portail Azure (GUI)

1. Connecte-toi sur <https://portal.azure.com>.
2. **Virtual machines** → ta VM → **Networking** (ou **Network settings**) : note le nom de la NIC.
3. **Public IP addresses** → `my-public-ip` → **Overview** → **Associate**.
4. **Resource type** : **Network interface** ; **Resource** : la NIC de la VM ; **IP configuration** : `ipconfig1` → **OK**.
5. Vérifie : sur l'**Overview** de la VM, le champ **Public IP address** affiche l'adresse de `my-public-ip`.

Chemin alternatif : **Network interfaces** → ta NIC → **IP configurations** → `ipconfig1` → **Public IP address** : **Associate** → choisis `my-public-ip` → **Save**.

## Méthode 2 : Azure CLI

```bash
RG="mon-groupe-de-ressources"

NIC=$(az vm nic list -g "$RG" --vm-name my-vm --query "[0].id" -o tsv | awk -F/ '{print $NF}')
IPCONFIG=$(az network nic ip-config list -g "$RG" --nic-name "$NIC" --query "[0].name" -o tsv)

az network nic ip-config update \
  -g "$RG" \
  --nic-name "$NIC" \
  -n "$IPCONFIG" \
  --public-ip-address my-public-ip
```

Si l'IP publique est dans un autre groupe de ressources, passe son **ID complet** à `--public-ip-address`.

## Méthode 3 : Terraform

### Deux situations

**Nouveau déploiement (tu crées la NIC avec Terraform).** C'est le cas normal : on référence l'IP publique dans la configuration IP de la NIC.

```hcl
resource "azurerm_public_ip" "this" {
  name                = "my-public-ip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "this" {
  name                = "my-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.this.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.this.id   # l'association
  }
}
```

**VM et IP publique déjà existantes (cette tâche).** `azurerm` n'a pas de ressource dédiée « associer une IP publique à une NIC existante » : l'IP est une propriété de la configuration IP de la NIC. Gérer la NIC avec `azurerm_network_interface` obligerait à l'importer et à recopier ses paramètres. Une approche plus légère utilise le provider `azapi`, qui envoie **uniquement** la modification de la configuration IP à l'API Azure. La suite de cette section l'utilise. La VM peut rester allumée.

Pourquoi un module ? Un module se réutilise (seules ses entrées changent). Le contre-exemple : copier-coller le même bloc de ressource dans chaque projet.

### Structure du projet

```
attach-public-ip/
├── providers.tf
├── variables.tf
├── main.tf                     # racine : contient module "nic_public_ip"
├── outputs.tf
├── terraform.tfvars            # contient des secrets : ne jamais le versionner
├── .gitignore
└── modules/
    └── nic_public_ip/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

### `providers.tf`

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}

  # Nécessaire quand le Service Principal n'a pas de droits au niveau de l'abonnement
  resource_provider_registrations = "none"

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}
```

### `variables.tf`

```hcl
variable "subscription_id" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "client_id" {
  type = string
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "resource_group_name" {
  type = string
}

variable "vm_name" {
  type    = string
  default = "my-vm"
}

variable "public_ip_name" {
  type    = string
  default = "my-public-ip"
}
```

### `main.tf` (racine)

```hcl
# VM existante : lue, pas gérée
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

# IP publique existante à associer
data "azurerm_public_ip" "pip" {
  name                = var.public_ip_name
  resource_group_name = var.resource_group_name
}

# NIC de la VM, lues via l'API Azure
data "azapi_resource" "vm" {
  type                   = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id            = data.azurerm_virtual_machine.vm.id
  response_export_values = ["properties.networkProfile.networkInterfaces"]
}

locals {
  # La première NIC de la VM est la NIC primaire
  nic_id = data.azapi_resource.vm.output.properties.networkProfile.networkInterfaces[0].id
}

# Configuration IP actuelle de cette NIC
data "azapi_resource" "nic" {
  type                   = "Microsoft.Network/networkInterfaces@2024-01-01"
  resource_id            = local.nic_id
  response_export_values = ["properties.ipConfigurations"]
}

module "nic_public_ip" {
  source = "./modules/nic_public_ip"

  nic_id           = local.nic_id
  ip_configuration = data.azapi_resource.nic.output.properties.ipConfigurations[0]
  public_ip_id     = data.azurerm_public_ip.pip.id
}
```

### `outputs.tf`

```hcl
output "public_ip_address" {
  value = data.azurerm_public_ip.pip.ip_address
}

output "nic_id" {
  value = local.nic_id
}
```

### `modules/nic_public_ip/variables.tf`

```hcl
variable "nic_id" {
  type        = string
  description = "ID de la NIC existante"
}

variable "ip_configuration" {
  type        = any
  description = "Configuration IP actuelle de la NIC (lue via l'API Azure)"
}

variable "public_ip_id" {
  type        = string
  description = "ID de l'IP publique à associer"
}
```

### `modules/nic_public_ip/main.tf`

```hcl
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

locals {
  ipc   = var.ip_configuration
  props = local.ipc.properties

  # privateIPAddress n'est repris que si l'allocation est Static
  static_private_ip = {
    for k, v in { privateIPAddress = try(local.props.privateIPAddress, "") } :
    k => v if local.props.privateIPAllocationMethod == "Static"
  }
}

resource "azapi_update_resource" "this" {
  type        = "Microsoft.Network/networkInterfaces@2024-01-01"
  resource_id = var.nic_id

  body = {
    properties = {
      ipConfigurations = [
        {
          name = local.ipc.name
          properties = merge(
            {
              subnet                    = { id = local.props.subnet.id }
              privateIPAllocationMethod = local.props.privateIPAllocationMethod
              primary                   = try(local.props.primary, true)
              publicIPAddress           = { id = var.public_ip_id }
            },
            local.static_private_ip
          )
        }
      ]
    }
  }
}
```

### `modules/nic_public_ip/outputs.tf`

```hcl
output "nic_id" {
  value = azapi_update_resource.this.resource_id
}
```

### `terraform.tfvars` (tes propres valeurs, sans chevrons)

```hcl
resource_group_name = "mon-groupe-de-ressources"

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
client_secret   = "ton-client-secret"
```

### `.gitignore`

```gitignore
*.tfvars
.terraform/
*.tfstate
*.tfstate.*
```

### Où trouver les quatre identifiants

| Variable | Où |
|---|---|
| `subscription_id` | Portail → Subscriptions → ton abonnement → Overview |
| `tenant_id` | Portail → Microsoft Entra ID → Overview |
| `client_id` | Entra ID → App registrations → ton application → *Application (client) ID* |
| `client_secret` | Même application → Certificates & secrets → New client secret → copie la colonne **Value** (affichée une seule fois) |

Donne ensuite à l'application le rôle **Contributor** sur le groupe de ressources (Resource group → Access control (IAM) → Add role assignment). Si ton environnement fournit des identifiants prêts à l'emploi, utilise-les à la place : ils peuvent changer à chaque session.

### Exécution (la VM peut rester allumée)

```bash
terraform init
terraform validate
terraform plan      # attendu : Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

Remarques :

- Le `main.tf` qui contient `module "nic_public_ip"` est celui de la **racine** du dossier, pas celui qui se trouve dans `modules/`.
- Le module modifie la **première** configuration IP de la **première** NIC de la VM, ce qui est le cas standard. Pour une NIC avec plusieurs configurations IP, cible la bonne.

## Vérification finale (toutes méthodes)

```bash
# La VM expose l'IP publique
az vm show -d -g "$RG" -n my-vm \
  --query "{ipPublique:publicIps, provisioning:provisioningState, power:powerState}" -o table

# associeA doit se terminer par .../networkInterfaces/<NIC>/ipConfigurations/<ipconfig>
az network public-ip show -g "$RG" -n my-public-ip \
  --query "{ip:ipAddress, associeA:ipConfiguration.id}" -o json

# Côté NIC
az network nic ip-config show -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" \
  --query "publicIPAddress.id" -o tsv
```

Attendu : `ipPublique` renseigné (même adresse que `ip`), `associeA` non vide, et un ID se terminant par `my-public-ip`.

## Remise à zéro (pour tester une autre méthode)

```bash
az network nic ip-config update -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" --remove publicIpAddress
```

(Ou portail : **Public IP addresses → my-public-ip → Dissociate**.) Supprime aussi le state local de l'essai précédent (`rm -f terraform.tfstate*`), sinon Terraform croira l'association déjà faite. `terraform destroy` ne dissocie **pas** l'IP : cette ressource ne fait qu'envoyer une modification, elle ne sait pas l'annuler.

## Dépannage

| Erreur | Cause | Solution |
|---|---|---|
| IP publique déjà utilisée | `my-public-ip` est associée à une autre NIC | Vérifier `associeA`, la dissocier d'abord |
| Erreur de région | IP publique et NIC dans des régions différentes | Elles doivent partager la région |
| `ipPublique` vide alors que l'association est faite | IP dynamique sur une VM désallouée | Démarrer la VM, ou utiliser une IP statique |
| SSH ou RDP refusé malgré l'IP publique | Aucune règle NSG n'autorise le port | Ajouter une règle NSG pour le port |
| `403 AuthorizationFailed ... register/action` sur de nombreux providers | `azurerm` 4.x tente d'enregistrer ~30 Resource Providers sur tout l'abonnement | Ajouter `resource_provider_registrations = "none"` dans le bloc provider |
| Même erreur, ou erreur d'authentification, avec un `providers.tf` vide | Sans bloc provider, les identifiants sont ignorés | Remplir `providers.tf` |
| Terraform demande des variables déjà présentes dans ton tfvars | Le fichier n'est pas chargé automatiquement (mauvais nom comme `terraform.tfvars.txt`, mauvais dossier) | Le nommer exactement `terraform.tfvars`, à côté de `main.tf`, ou passer `-var-file="fichier.tfvars"` |
| `Invalid client secret` | Secret vide, tronqué, ou *Secret ID* copié à la place de *Value* | Recréer un secret et copier la colonne **Value** |
| `Module not installed` | `terraform init` n'a pas été lancé | Lancer `terraform init` |
| `No declaration found for var.xxx`, ou soulignements rouges dans VS Code | Un `variables.tf` manque à la racine, ou l'éditeur n'a pas rechargé | Vérifier les fichiers avec `find`, lancer `terraform init` et `terraform validate` ; si valide, **Developer: Reload Window** |
| Erreur sur `.output.properties...` | La sortie `azapi` a une autre forme | Afficher la NIC avec `az network nic show -o json` et adapter le chemin |
| Erreur de type sur `merge` ou `ip_configuration` | NIC inhabituelle (plusieurs configurations IP, IPv6) | Cibler explicitement la bonne configuration IP |
| `ResourceNotFound` sur une `data` source | Mauvais nom de groupe, ou VM encore en cours de création | Vérifier les noms et attendre `provisioningState = Succeeded` |
| Ancien état ou anciens identifiants après une nouvelle session | Le fichier d'état et les identifiants appartiennent à un environnement précédent | Utiliser un nouveau dossier et les identifiants de la session en cours |

## Nettoyage

```bash
# CLI
az network nic ip-config update -g "$RG" --nic-name "$NIC" -n "$IPCONFIG" --remove publicIpAddress
```

`terraform destroy` ne dissocie pas l'IP (voir plus haut).

## Notes de sécurité

- Ne jamais versionner `terraform.tfvars` ni les fichiers d'état : ils contiennent un secret et des détails de ressources.
- Préférer des secrets à durée de vie courte et le rôle le moins privilégié (Contributor sur un groupe de ressources, pas sur l'abonnement).
- Une IP publique expose la VM à Internet : n'ouvre dans le NSG que les ports nécessaires, et préfère le SSH par clé.
- Exécute les trois méthodes l'une après l'autre en annulant la modification entre chaque essai : une configuration IP ne porte qu'une seule IP publique.
