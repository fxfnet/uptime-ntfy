# uptime-ntfy

Sonde GitHub Actions toutes les 5 minutes sur go2prod.com, toysfab.com et matherialise.com.

- Un site est déclaré indisponible après 2 échecs consécutifs (réponse hors 2xx/3xx ou délai de 20 s dépassé), à 30 s d'intervalle.
- Une alerte ntfy priorité `urgent` part au passage à l'état indisponible, une notification normale au rétablissement. Aucune répétition entre les deux.
- L'état de chaque site est conservé dans `state/`.
- Le topic ntfy est stocké dans le secret `NTFY_TOPIC`.

Ajouter un site : une ligne dans `sites.txt`.

Tester la chaîne de notification : Actions > uptime > Run workflow, cocher « Envoyer une notification de test ».
