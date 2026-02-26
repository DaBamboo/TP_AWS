TP 5 : Haute disponibilité ALB public, ASG privé, health checks

On a utilisé Terraform pour réaliser ce TP. Tous les fichiers ont été uploadés et sont consultables.
On a d'abord déclaré notre cloud provider, région, profil dans le fichier version.tf

On a ensuite déclaré toutes nos variables et leurs valeurs dans les fichiers variables.tf et terraform.vars
Puis l'intégralité a été faite dans main.tf

On a également créé un fichier outputs.tf pour récupérer directement l'url
![alt text](image-1.png)

Après avoir fait le terraform apply :
![alt text](image.png)

On peut consulter directement l'url dans notre navigateur, en HTTP car bien que nous ayons pris les dispositions de sécurité dans le cadre du TP (redirection...), on n'a en réalité pas de certificat.
On doit donc effectuer les tests sur le port 8080.

Le résultat du healthcheck est disponible dans le fichier HealthCheck.json

```
aws autoscaling describe-auto-scaling-groups `
>>   --auto-scaling-group-names "tp5-asg" `
>>   --query "AutoScalingGroups[0].Instances[*].{ID:InstanceId,AZ:AvailabilityZone,State:LifecycleState,Health:HealthStatus}" `
>>   --output table `
>>   --profile training
```
On voit bien nos deux instances :
---------------------------------------------------------------
|                  DescribeAutoScalingGroups                  |
+------------+----------+-----------------------+-------------+
|     AZ     | Health   |          ID           |    State    |
+------------+----------+-----------------------+-------------+
|  eu-west-3b|  Healthy |  i-055b7a4016c213447  |  InService  |
|  eu-west-3a|  Healthy |  i-0cf945baf422d56f1  |  InService  |
+------------+----------+-----------------------+-------------+

Après avoir terminé une des instances, on voit qu'une nouvelle s'est créée et que notre instance est en train d'être terminée :
-------------------------------------------------------------------
|                    DescribeAutoScalingGroups                    |
+------------+------------+-----------------------+---------------+
|     AZ     |  Health    |          ID           |     State     |
+------------+------------+-----------------------+---------------+
|  eu-west-3b|  Unhealthy |  i-055b7a4016c213447  |  Terminating  |
|  eu-west-3b|  Healthy   |  i-09183e9de965e0c61  |  InService    |
|  eu-west-3a|  Healthy   |  i-0cf945baf422d56f1  |  InService    |
+------------+------------+-----------------------+---------------+

après quelques temps, on voit qu'on a bien deux instances actives mais avec ID différents par rapport au début :
---------------------------------------------------------------
|                  DescribeAutoScalingGroups                  |
+------------+----------+-----------------------+-------------+
|     AZ     | Health   |          ID           |    State    |
+------------+----------+-----------------------+-------------+
|  eu-west-3b|  Healthy |  i-09183e9de965e0c61  |  InService  |
|  eu-west-3a|  Healthy |  i-0cf945baf422d56f1  |  InService  |
+------------+----------+-----------------------+-------------+