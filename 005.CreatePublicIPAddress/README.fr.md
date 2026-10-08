# Adresse IP publique Azure : GUI, Azure CLI et Terraform

🌐 **Langues :** **Français** · [English](README.en.md) · [Deutsch](README.de.md)

## Contexte

Une entreprise migre une partie de son infrastructure vers Azure. Pour limiter les risques, la migration est découpée en petites étapes indépendantes plutôt qu'en un seul grand basculement. La première brique est une **adresse IP publique** : une adresse joignable depuis Internet, qui pourra ensuite être attachée à une machine virtuelle, un load balancer ou une passerelle.

**Objectif :** créer une adresse IP publique nommée `datacenter-pip` dans un groupe de ressources existant.

## Concepts clés

| Concept | Exemple | Contre-exemple |
|---|---|---|
| IP publique vs privée | `20.50.10.4` est joignable depuis Internet (ex. SSH) | `10.0.0.4` n'est joignable qu'à l'intérieur du réseau Azure |
| Allocation statique | L'adresse ne change jamais, même si la VM est arrêtée : les enregistrements DNS restent valides | Une adresse dynamique peut changer après un arrêt/démarrage, et le DNS pointe alors dans le vide |
| SKU Standard | Sécurisé par défaut (fermé tant qu'un Network Security Group n'autorise pas le trafic) | Le SKU Basic est retiré par Azure (depuis le 30 septembre 2025) : ne pas l'utiliser |

Pourquoi créer l'IP séparément de la VM ? Elle peut survivre à la VM : si la VM est détruite puis recréée, l'adresse (et les règles de pare-feu qui la référencent) reste identique.

## Prérequis

- Un abonnement Azure et un **groupe de ressources existant** (note son nom et sa région).
- Pour la méthode Terraform : Terraform >= 1.5 installé sur ta machine. Azure CLI **n'est pas** nécessaire.
- Pour la méthode Terraform : un **Service Principal** (client ID + client secret) avec le rôle *Contributor* sur le groupe de ressources, ainsi que le tenant ID et le subscription ID.

## Méthode 1 : portail Azure (GUI)

1. Connecte-toi sur <https://portal.azure.com>.
2. Recherche **Public IP addresses**, ouvre le service puis clique sur **Create**.
3. Renseigne :
   - **Subscription** et **Resource group** : ceux qui existent déjà
   - **Region** : la même que le groupe de ressources
   - **Name** : `datacenter-pip`
   - **IP Version** : IPv4
   - **SKU** : Standard
   - **Assignment** : Static
4. Clique sur **Review + create**, puis **Create**.
5. Vérifie que `datacenter-pip` apparaît dans la liste avec une adresse IP.

## Méthode 2 : Azure CLI

```bash
az login

RG="mon-groupe-de-ressources"   # remplace par le nom de ton groupe de ressources
LOCATION="eastus"               # remplace par sa région

az network public-ip create \
  --resource-group "$RG" \
  --name datacenter-pip \
  --location "$LOCATION" \
  --sku Standard \
  --allocation-method Static

# Vérifier
az network public-ip show \
  --resource-group "$RG" \
  --name datacenter-pip \
  --query "{nom:name, ip:ipAddress, sku:sku.name, allocation:publicIPAllocationMethod}" -o table
```

> Dans un shell, `<` et `>` sont des opérateurs de redirection. Ne colle jamais des emplacements comme `<RG>` tels quels : remplace-les par de vraies valeurs.

## Méthode 3 : Terraform (modules, exécuté depuis ta machine)

### Structure du projet

```
azure-public-ip/
├── providers.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── terraform.tfvars        # contient des secrets : ne jamais le versionner
└── modules/
    └── public_ip/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

Un module se réutilise pour chaque future IP publique (seul le nom change). Le contre-exemple : copier-coller un bloc `azurerm_public_ip` dans chaque projet et corriger chaque copie à la main.

### Module (`modules/public_ip/`)

`variables.tf`
```hcl
variable "name" {
  type        = string
  description = "Nom de l'IP publique"
}

variable "resource_group_name" {
  type        = string
  description = "Groupe de ressources existant"
}

variable "location" {
  type        = string
  description = "Région Azure"
}

variable "allocation_method" {
  type    = string
  default = "Static"
}

variable "sku" {
  type    = string
  default = "Standard"
}
```

`main.tf`
```hcl
resource "azurerm_public_ip" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = var.allocation_method
  sku                 = var.sku
}
```

`outputs.tf`
```hcl
output "id" {
  value = azurerm_public_ip.this.id
}

output "ip_address" {
  value = azurerm_public_ip.this.ip_address
}
```

### Configuration racine

`providers.tf`
```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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
```

`variables.tf`
```hcl
variable "resource_group_name" {
  type = string
}

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
```

`main.tf`
```hcl
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

module "datacenter_pip" {
  source = "./modules/public_ip"

  name                = "datacenter-pip"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
}
```

`outputs.tf`
```hcl
output "datacenter_pip_address" {
  value = module.datacenter_pip.ip_address
}
```

`terraform.tfvars` (mets tes propres valeurs, sans chevrons)
```hcl
resource_group_name = "mon-groupe-de-ressources"

subscription_id = "00000000-0000-0000-0000-000000000000"
tenant_id       = "00000000-0000-0000-0000-000000000000"
client_id       = "00000000-0000-0000-0000-000000000000"
client_secret   = "ton-client-secret"
```

`.gitignore`
```gitignore
*.tfvars
.terraform/
*.tfstate
*.tfstate.*
```

### Exécution

```bash
terraform init
terraform validate
terraform plan      # attendu : Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

### Où trouver les quatre identifiants

| Variable | Où |
|---|---|
| `subscription_id` | Portail → Subscriptions → ton abonnement → Overview |
| `tenant_id` | Portail → Microsoft Entra ID → Overview |
| `client_id` | Entra ID → App registrations → ton application → *Application (client) ID* |
| `client_secret` | Même application → Certificates & secrets → New client secret → copie la colonne **Value** (affichée une seule fois) |

Donne ensuite à l'application le rôle **Contributor** sur le groupe de ressources (Resource group → Access control (IAM) → Add role assignment).

## Dépannage

| Erreur | Cause | Solution |
|---|---|---|
| `403 AuthorizationFailed ... register/action` sur de nombreux providers | `azurerm` 4.x tente d'enregistrer ~30 Resource Providers sur tout l'abonnement | Ajouter `resource_provider_registrations = "none"` dans le bloc provider |
| `"name" may only contain alphanumeric characters, dash, underscores, parentheses and periods` | La valeur du groupe de ressources contient encore des caractères d'exemple comme `<` `>` | Utiliser le vrai nom du groupe de ressources |
| Terraform demande des variables déjà présentes dans ton tfvars | Le fichier n'est pas chargé automatiquement (mauvais nom comme `terraform.tfvars.txt`, mauvais dossier) | Le nommer exactement `terraform.tfvars` à la racine du projet, ou passer `-var-file="fichier.tfvars"` |
| `Invalid client secret` | Secret vide, tronqué, ou *Secret ID* copié à la place de *Value* | Recréer un secret et copier la colonne **Value** |
| `already exists` à l'apply | L'IP a déjà été créée avec une autre méthode | La supprimer d'abord (`az network public-ip delete -g "$RG" -n datacenter-pip`) ou l'importer |

## Nettoyage

```bash
terraform destroy
# ou
az network public-ip delete --resource-group "$RG" --name datacenter-pip
```

## Notes de sécurité

- Ne jamais versionner `terraform.tfvars` ni le fichier d'état : ils contiennent un secret et des détails de ressources.
- Préférer des secrets à durée de vie courte et le rôle le moins privilégié (Contributor sur un groupe de ressources, pas sur l'abonnement).
- Exécute les trois méthodes l'une après l'autre en supprimant l'IP entre chaque essai : une ressource du même nom ne peut pas être créée deux fois.
