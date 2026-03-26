A partir du TP7, on a créé un dossier base regroupant toutes les informations ainsi que les ressources utiles et communes aux TPs pour éviter d'avoir à les refaire à chaque TP.


J'ai également voulu modifier la structure pour ne plus avoir à redéclarer tous mes IDs et autre éléments communs à chaque fois que je faisais un nouveau TP. 

Désormais, j'ai un fichier terraform.tfstate (non posté (ajouté au .gitignore) pour raisons de sécurité car contient des données sensibles) dans mon dossier base qui contient toutes ces informations. 
Je fais appel au contenu de ce dossier dans mes TP via terraform_remote_state :

```
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../base/terraform.tfstate"
  }
}
```
