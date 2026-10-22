#!/usr/bin/env python3
"""Read-only Morea report using the same authenticated API as the MCP plugin."""
import json
import os
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

QUERY = """query {
  auditStore(limit: 2000) {
    summary { productCount collectionCount issueCount autoFixableCount bySeverity byCode }
  }
  inventorySummary { trackedProducts untrackedProducts lowStockCount outOfStockCount totalUnits }
  stats { from to placedCount deliveredCount deliveredRevenueDh cancelRate returnRate
    pipeline { status count } }
}"""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Morea API redirects are not allowed")


def report(endpoint, token):
    url = urlsplit(endpoint)
    if url.scheme != "https" or not url.hostname or url.username or url.password or url.fragment:
        raise ValueError("MOREA_GRAPHQL_URL must be an HTTPS endpoint without credentials or fragment")
    request = Request(endpoint, data=json.dumps({"query": QUERY}).encode(), headers={
        "Authorization": "Bearer " + token,
        "Content-Type": "application/json",
    })
    with build_opener(NoRedirect).open(request, timeout=60) as response:
        # Never forward a bearer token to another host via a redirect.
        if urlsplit(response.url).netloc != url.netloc:
            raise ValueError("Unexpected API response origin")
        result = json.load(response)
    if result.get("errors") or not result.get("data") or any(value is None for value in result["data"].values()):
        raise RuntimeError("Morea report query failed; check token access and deployed API schema")
    return result["data"]


def main():
    token = os.environ.get("MOREA_API_TOKEN", "")
    if not token:
        raise RuntimeError("Configure the MOREA_API_TOKEN GitHub Actions secret")
    data = report(os.environ.get("MOREA_GRAPHQL_URL", "https://morea.ollazen.com/graphql"), token)
    output = Path("reports")
    output.mkdir(exist_ok=True)
    (output / "store-report.json").write_text(json.dumps(data, indent=2) + "\n")
    audit = data["auditStore"]["summary"]
    stock = data["inventorySummary"]
    stats = data["stats"]
    summary = (f"Morea store report ({stats['from']} to {stats['to']})\n\n"
               f"Products audited: {audit['productCount']} (limit 2,000; larger catalogs are partial)\n"
               f"Catalog issues: {audit['issueCount']}\n"
               f"Low stock: {stock['lowStockCount']}; out of stock: {stock['outOfStockCount']}\n"
               f"Orders placed: {stats['placedCount']}; delivered: {stats['deliveredCount']}\n"
               f"Cash collected: {stats['deliveredRevenueDh']} DH\n")
    print(summary)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as stream:
            stream.write(summary)


if __name__ == "__main__":
    main()
