# uptime-ntfy

Sonde GitHub Actions toutes les 5 minutes sur go2prod.com, toysfab.com et matherialise.com.

- Un site est déclaré indisponible après 2 échecs consécutifs (réponse hors 2xx/3xx ou délai de 20 s dépassé), à 30 s d'intervalle.
- Une alerte ntfy priorité `urgent` part au passage à l'état indisponible, une notification normale au rétablissement. Aucune répétition entre les deux.
- L'état de chaque site est conservé dans `state/`.
- Le topic ntfy est stocké dans le secret `NTFY_TOPIC`.

Ajouter un site : une ligne dans `sites.txt`.

Tester la chaîne de notification : Actions > uptime > Run workflow, cocher « Envoyer une notification de test ».

## Machines internes (battement de cœur)

Une machine non joignable depuis Internet (réseau local, Tailscale) envoie elle-même un battement toutes les 5 minutes sur le topic ntfy `<NTFY_TOPIC>-hb`. La sonde lit ce topic et alerte si aucun battement n'est arrivé depuis 15 minutes.

Machines suivies : `heartbeats.txt`. Le nom doit être identique au message envoyé.

Ligne crontab à installer sur la machine (`crontab -e`), en remplaçant `<NOM>` et `<TOPIC>` :

```
*/5 * * * * curl -fsS -m 10 -H "Priority: min" -d <NOM> https://ntfy.sh/<TOPIC>-hb >/dev/null 2>&1
```
