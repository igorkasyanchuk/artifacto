# Security

Artifacto hosts arbitrary HTML and JavaScript uploaded by anyone, so its isolation
is the product. Reports about it are very welcome.

## Reporting a vulnerability

Please report privately through GitHub's
[private vulnerability reporting](https://github.com/igorkasyanchuk/artifacto/security/advisories/new),
not in a public issue. Include what an attacker gains and the steps to reproduce.
Expect an acknowledgement within a few days.

In scope, in particular:

- an artifact reading or writing anything on the app origin — cookies, storage,
  the comment overlay, another artifact;
- an artifact escaping its sandbox: top-level navigation, popups, downloads, form
  posts, or network access without `allow_network`;
- markup or script from a comment, title or report running anywhere;
- reading a PIN-locked artifact, its comments or metadata without the PIN;
- changing or deleting an artifact or comment without its edit token;
- getting into `/admin` without an admin account.

Out of scope: phishing or other abusive *content* hosted on an instance — use the
Report form on the artifact, or the contact on that instance's `/terms` page — and
anything the README already names as a known cost of single-origin mode.

## Abuse on the public instance

For abusive content on <https://artifacto.igorkasyanchuk.com>, use the Report form
on the artifact page or the address on its [terms page](https://artifacto.igorkasyanchuk.com/terms).
