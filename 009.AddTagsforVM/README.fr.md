# Ajouter et gérer des tags sur une machine virtuelle Azure : GUI, Azure CLI et Terraform

🌐 **Langues :** **Français** · [English](README.en.md) · [Deutsch](README.de.md)

## Contexte

Une entreprise migre une partie de son infrastructure vers Azure. Pendant la migration, plusieurs machines virtuelles (VM) ont été créées dans différentes régions, et certaines ne sont pas étiquetées correctement. Cette tâche est l'une des étapes de remise en ordre : **ajouter le tag `Environment=dev` à une VM existante**.

Dans ce README, la VM s'appelle `my-vm`. Remplace ce nom par le tien.

La tâche est résolue de trois façons :

1. **Portail Azure (GUI)**
2. **Azure CLI**
3. **Terraform** (module, exécuté depuis ta propre machine, **sans** Azure CLI)

## Qu'est-ce qu'un tag et pourquoi l'utiliser

Un **tag** est une étiquette clé/valeur posée sur une ressource Azure, ici `Environment` = `dev`. Il ne change rien au comportement de la VM : il sert à la classer, la retrouver et la facturer.

| Concept | Exemple | Contre-exemple |
|---|---|---|
| Tag Azure | `Environment=dev` posé sur la ressource `my-vm` : visible dans le portail, les rapports de coûts et les politiques | Une étiquette écrite dans un fichier à l'intérieur de la VM : Azure ne la voit pas |
| Ajouter (merge) | On ajoute `Environment=dev` et les tags existants (`Owner`, `Project`…) restent | Une commande qui **remplace** : tous les anciens tags disparaissent |
| Valeur exacte | `Environment=dev` | `Environment=Dev` : le **nom** du tag n'est pas sensible à la casse, mais la **valeur** l'est, donc ce n'est pas la même étiquette pour une vérification |
| Pas d'héritage | Le tag est sur la VM | Un tag posé sur le groupe de ressources n'est pas copié sur la VM, et celui de la VM n'est pas copié sur sa NIC ni ses disques |

Usages réels :

- **Répartition des coûts** : un rapport Cost Management groupé par `Environment` sépare dev, test et production.
- **Gouvernance** : une politique Azure peut exiger un tag, ou une automatisation peut éteindre la nuit toutes les VM `Environment=dev`.
- **Recherche** : filtrer la liste des ressources par tag.

## Procédure générale : étiqueter une VM

Ces étapes valent pour n'importe quelle VM, quel que soit l'outil utilisé.

| Étape | Que faire | Pourquoi |
|---|---|---|
| 1. Retrouver la VM | Chercher la VM par son nom dans toutes les régions pour obtenir son groupe de ressources | Les VM d'une même migration peuvent être dans des régions différentes |
| 2. Lire les tags actuels | Afficher les tags déjà présents sur la VM | Il faudra pouvoir vérifier ensuite qu'aucun n'a été perdu |
| 3. Ajouter le tag en **merge** | Panneau **Tags** du portail, `az tag update --operation merge`, ou Terraform | Le merge conserve les tags existants |
| 4. Vérifier | Réafficher les tags | Confirme que `Environment=dev` est présent et que les autres sont intacts |

À savoir :

- Ajouter un tag **ne redémarre pas** la VM et n'affecte pas son fonctionnement.
- Un nom de tag ne peut pas contenir `<`, `>`, `%`, `&`, `\`, `?` ni `/`.
- Une ressource porte au plus 50 tags.

## Prérequis

- Un abonnement Azure et le **groupe de ressources** qui contient la VM (note son nom).
- Pour Terraform : Terraform >= 1.5 sur ta machine (n'importe quel shell, par exemple Git Bash). Azure CLI **n'est pas** nécessaire.
- Pour Terraform : un **Service Principal** (client ID + client secret) avec le rôle *Contributor* sur le groupe de ressources, ainsi que le tenant ID et le subscription ID.

> Dans un shell, `<` et `>` sont des opérateurs de redirection. Ne colle jamais des emplacements comme `<RG>` tels quels : remplace-les par de vraies valeurs.

## Avant de commencer : retrouver la VM et ses tags

```bash
# La VM peut être dans n'importe quelle région : on la cherche par son nom
az vm list --query "[?name=='my-vm'].{groupe:resourceGroup, region:location}" -o table

RG="mon-groupe-de-ressources"      # valeur de la colonne « groupe », sans chevrons

# Tags actuels (null ou {} si aucun)
az vm show -g "$RG" -n my-vm --query tags -o json
```

Note les tags existants : à la fin, ils doivent **tous** être encore là.

## Méthode 1 : portail Azure (GUI)

1. Connecte-toi sur <https://portal.azure.com>.
2. **Virtual machines** → `my-vm`.
3. Menu de gauche : **Tags**.
4. Dans la première ligne vide : **Name** = `Environment`, **Value** = `dev`.
5. Clique sur **Apply** en bas de la page. Sans cela, rien n'est enregistré.
6. Vérifie : la page **Tags** (ou **Overview**) affiche `Environment : dev`.

## Méthode 2 : Azure CLI

```bash
RG="mon-groupe-de-ressources"

VM_ID=$(az vm show -g "$RG" -n my-vm --query id -o tsv)

az tag update --resource-id "$VM_ID" --operation merge --tags Environment=dev
```

`--operation merge` ajoute le tag **sans effacer** les autres.

Variante équivalente, avec `az vm update` :

```bash
az vm update -g "$RG" -n my-vm --set tags.Environment=dev
```

**À éviter** : `az resource tag --tags Environment=dev ...` sans l'option `--is-incremental` **remplace** tous les tags existants par ce seul tag.

## Méthode 3 : Terraform

### Deux situations

**Nouveau déploiement (tu crées la VM avec Terraform).** C'est le cas normal : on renseigne `tags` sur la ressource VM.

```hcl
resource "azurerm_linux_virtual_machine" "this" {
  name                = "my-vm"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  # ... taille, image, interfaces réseau, identifiants ...

  tags = {
    Environment = "dev"
  }
}
```

**VM déjà existante (cette tâche).** `tags` est une propriété de la VM elle-même. Gérer la VM avec `azurerm_linux_virtual_machine` obligerait à l'importer et à recopier tous ses paramètres (taille, image, clé SSH…), avec un risque de remplacement. Une approche plus légère utilise le provider `azapi`, qui envoie **uniquement** la modification des tags à l'API Azure. Le provider fusionne le corps de la requête avec la ressource existante, donc les autres tags doivent rester : compare `az vm show --query tags` avant et après. La suite de cette section l'utilise.

Pourquoi un module ? Un module se réutilise (seules ses entrées changent). Le contre-exemple : copier-coller le même bloc de ressource dans chaque projet.

### Structure du projet

```
tag-vm/
├── providers.tf
├── variables.tf
├── main.tf                     # racine : contient module "vm_tags"
├── outputs.tf
├── terraform.tfvars            # contient des secrets : ne jamais le versionner
├── .gitignore
└── modules/
    └── vm_tags/
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

variable "tags" {
  type = map(string)
  default = {
    Environment = "dev"
  }
}
```

### `main.tf` (racine)

```hcl
# VM existante : lue, pas gérée
data "azurerm_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
}

module "vm_tags" {
  source = "./modules/vm_tags"

  vm_id = data.azurerm_virtual_machine.vm.id
  tags  = var.tags
}
```

### `outputs.tf`

```hcl
output "vm_id" {
  value = module.vm_tags.vm_id
}

output "applied_tags" {
  value = module.vm_tags.tags
}
```

### `modules/vm_tags/variables.tf`

```hcl
variable "vm_id" {
  type        = string
  description = "ID de la VM existante"
}

variable "tags" {
  type        = map(string)
  description = "Tags à ajouter à la VM"
}
```

### `modules/vm_tags/main.tf`

```hcl
terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

resource "azapi_update_resource" "this" {
  type        = "Microsoft.Compute/virtualMachines@2024-03-01"
  resource_id = var.vm_id

  body = {
    tags = var.tags
  }
}
```

### `modules/vm_tags/outputs.tf`

```hcl
output "vm_id" {
  value = azapi_update_resource.this.resource_id
}

output "tags" {
  value = var.tags
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

### Exécution

```bash
terraform init
terraform validate
terraform plan      # attendu : Plan: 1 to add, 0 to change, 0 to destroy
terraform apply
```

Remarques :

- La VM n'a besoin ni d'être arrêtée ni d'être redémarrée.
- Le `main.tf` qui contient `module "vm_tags"` est celui de la **racine** du dossier, pas celui qui se trouve dans `modules/`.
- `terraform destroy` ne retire **pas** le tag : cette ressource ne fait qu'envoyer une modification, elle ne sait pas l'annuler.

## Vérification finale (toutes méthodes)

```bash
az vm show -g "$RG" -n my-vm --query tags -o json

# Autre lecture, via l'API des tags
az tag list --resource-id "$(az vm show -g "$RG" -n my-vm --query id -o tsv)" -o json
```

Attendu : `"Environment": "dev"` est présent, et les tags notés au départ sont toujours là.

## Remise à zéro (pour tester une autre méthode)

```bash
az vm update -g "$RG" -n my-vm --remove tags.Environment
```

Supprime aussi le state local de l'essai précédent (`rm -f terraform.tfstate*`), sinon Terraform croira le tag déjà posé.

## Dépannage

| Erreur | Cause | Solution |
|---|---|---|
| Les anciens tags ont disparu | Commande qui remplace (`az resource tag` sans `--is-incremental`, ou `--operation replace`) | Utiliser `--operation merge`, puis ré-ajouter les tags perdus |
| Tag non enregistré dans le portail | Clic sur **Apply** oublié | Revenir sur **Tags** et cliquer sur **Apply** |
| `Environment=Dev` au lieu de `dev` | La valeur est sensible à la casse | Corriger la valeur en `dev` |
| Caractères interdits dans le nom du tag | Un nom ne peut pas contenir `<`, `>`, `%`, `&`, `\`, `?`, `/` | Choisir un nom sans ces caractères |
| Plus de 50 tags | Limite Azure par ressource | Supprimer des tags inutiles |
| VM introuvable | Mauvais nom de groupe, ou VM dans une autre région | Reprendre la colonne « groupe » de la recherche ci-dessus |
| `403 AuthorizationFailed ... register/action` sur de nombreux providers | `azurerm` 4.x tente d'enregistrer ~30 Resource Providers sur tout l'abonnement | Ajouter `resource_provider_registrations = "none"` dans le bloc provider |
| Même erreur, ou erreur d'authentification, avec un `providers.tf` vide | Sans bloc provider, les identifiants sont ignorés | Remplir `providers.tf` |
| Terraform demande des variables déjà présentes dans ton tfvars | Le fichier n'est pas chargé automatiquement (mauvais nom comme `terraform.tfvars.txt`, mauvais dossier) | Le nommer exactement `terraform.tfvars`, à côté de `main.tf`, ou passer `-var-file="fichier.tfvars"` |
| `Invalid client secret` | Secret vide, tronqué, ou *Secret ID* copié à la place de *Value* | Recréer un secret et copier la colonne **Value** |
| `Module not installed` | `terraform init` n'a pas été lancé | Lancer `terraform init` |
| `No declaration found for var.xxx`, ou soulignements rouges dans VS Code | Un `variables.tf` manque à la racine, ou l'éditeur n'a pas rechargé | Vérifier les fichiers avec `find`, lancer `terraform init` et `terraform validate` ; si valide, **Developer: Reload Window** |
| Erreur `azapi` sur la mise à jour | Opération refusée ou forme de réponse inattendue | Afficher l'erreur et utiliser la CLI (`az tag update`) en secours |
| Ancien état ou anciens identifiants après une nouvelle session | Le fichier d'état et les identifiants appartiennent à un environnement précédent | Utiliser un nouveau dossier et les identifiants de la session en cours |

## Nettoyage

```bash
az vm update -g "$RG" -n my-vm --remove tags.Environment
```

`terraform destroy` ne retire pas le tag (voir plus haut).

## Notes de sécurité

- Ne jamais versionner `terraform.tfvars` ni les fichiers d'état : ils contiennent un secret et des détails de ressources.
- Préférer des secrets à durée de vie courte et le rôle le moins privilégié (Contributor sur un groupe de ressources, pas sur l'abonnement).
- Ne mets ni secret ni donnée personnelle dans un tag : les tags apparaissent dans les rapports de facturation et sont lisibles par quiconque peut lire la ressource.
- Exécute les trois méthodes l'une après l'autre en annulant la modification entre chaque essai, pour que chacune parte du même état.
