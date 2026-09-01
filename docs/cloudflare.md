# Cloudflare setup (DNS, proxy, TLS Full Strict, WAF)

Goal: the site sits behind Cloudflare — DNS hosted there, traffic proxied, TLS end-to-end in Full (Strict) mode with an origin certificate on nginx.

## 1. Move DNS to Cloudflare

1. cloudflare.com → sign up (Free plan) → **Add site** → enter your domain
2. Cloudflare assigns two nameservers (`xxx.ns.cloudflare.net`)
3. At your registrar (where the domain was bought): replace current NS records with the Cloudflare pair
4. Wait for propagation — usually minutes, up to a few hours: `dig NS your-domain.com +short` should return the Cloudflare nameservers

## 2. Point the site record

1. DNS → Records → **Add record**: `A`, name `site` (subdomain for this project), value = your server IP, **proxied** (orange cloud)
2. Test while DNS is off-proxy if needed: toggle the cloud to grey to check origin directly

## 3. TLS: Full (Strict) with an origin certificate

Flexible mode encrypts only browser→Cloudflare and is not acceptable here. Full (Strict) requires a certificate on the origin server — Cloudflare issues free 15-year origin certs:

1. SSL/TLS → **Origin Server** → **Create Certificate** → RSA, hostnames: `site.your-domain.com`
2. Save the certificate as `certs/origin.pem` and the private key as `certs/key.pem` on the server (repo root, `certs/` is gitignored — add it to `.gitignore` if missing)
3. Mount the certs into nginx and enable the TLS server block:
   - copy `nginx/tls.conf.sample` to `nginx/tls.conf`, set your `server_name`
   - in `docker-compose.yml`, nginx service: add volume `./certs:/etc/nginx/certs:ro`, add mapping of `nginx/tls.conf` into `conf.d/`, publish `443:443`
4. SSL/TLS → Overview → set mode to **Full (Strict)**
5. Edge Certificates → enable **Always Use HTTPS**

## 4. One useful WAF rule

Security → WAF → Custom rules → **Create rule**:

- Field: URI Path, operator: equals, value: `/wp-login.php`
- And: IP Source Address → does not equal → your home/office IP
- Action: **Block**

Admin panel now reachable only from your IP; Cloudflare absorbs the rest at the edge.

## 5. Verify

```bash
dig site.your-domain.com +short        # Cloudflare IPs, not your origin
curl -sI https://site.your-domain.com  # expect: server: cloudflare, cf-ray header, HTTP 200
```

Confirm the padlock chain in the browser: edge cert from Google Trust Services (Cloudflare), origin cert never exposed publicly.
