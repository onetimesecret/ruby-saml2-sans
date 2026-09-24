# XML Parser Selection for SAML in Ruby

*Researched: 2026-09-24*

**Conclusion:** Nokogiri is the only serious XML parser for a Ruby SAML implementation. SAML needs namespace-aware XPath and Exclusive XML Canonicalization (exc-c14n), and the whole implementation must use one parser. Ox and Oga do not provide those primitives. LibXML-Ruby does, but it sits on the same libxml2 as Nokogiri and adds nothing except API friction. REXML is unsafe on untrusted input and is the root cause of the 2025 ruby-saml parser-differential CVEs.

---

## 1. Ruby XML parser landscape

| Library | Type | Default security | Notes |
|---|---|---|---|
| **Nokogiri** | C ext (wraps libxml2) | Safe (v1.5.4+) | Most popular. `noent` disabled by default since 1.5.4. |
| **REXML** | Pure Ruby (stdlib) | Vulnerable | External entities expanded by default; vulnerable to billion-laughs DoS. |
| **Ox** | C ext (self-contained) | Safe | No external entity support at all, so inherently immune to XXE. No libxml2 dependency. |
| **LibXML-Ruby** | C ext (wraps libxml2) | Depends on config | Direct libxml2 bindings; security depends on configuration. |
| **Oga** | Mostly pure Ruby | Relatively safe | No libxml2 dependency; no known XXE issues. Lightly maintained. |

Source: [^xxe-page]

### Nokogiri

Safe by default, but easy to make unsafe [^xxe-page].

**The naming trap:** `NOENT` sounds like "no entities" but means *"expand all entities"* (libxml2 reads it as "no entity references left unexpanded"). `NONET` does what it sounds like and blocks network fetches [^safeguard].

```ruby
# BAD: enables entity expansion on untrusted input
doc = Nokogiri::XML(xml) { |config| config.noent }

# GOOD: defaults are already safe; add nonet as belt-and-suspenders
def parse_untrusted_xml(raw)
  Nokogiri::XML(raw) { |config| config.strict.nonet }
end
```

Sources: [^safeguard] [^codeql]

Never enable these on untrusted input [^xxe-page]:

- `Nokogiri::XML::ParseOptions::NOENT`
- `Nokogiri::XML::ParseOptions::DTDLOAD`
- `Nokogiri::XML::ParseOptions::DTDVALID`

### REXML

Vulnerable by default to XXE and billion-laughs DoS [^xxe-page]. Mitigations exist but are opt-in:

```ruby
# Option 1: reject DOCTYPE entirely (strictest)
raise SecurityError, "DOCTYPE not allowed" if xml_string =~ /<!DOCTYPE/i
doc = REXML::Document.new(xml_string)

# Option 2: limit entity expansion (softer)
REXML::Security.entity_expansion_limit = 1000
REXML::Security.entity_expansion_text_limit = 10_240
doc = REXML::Document.new(xml_string)
```

Avoid REXML for any untrusted input.

### Ox

No external entity support by design, so no XXE surface [^xxe-page]. Fast and free of libxml2, at the cost of XPath and namespace support.

---

## 2. Ruby 4.x changes nothing

Ruby 4.0 was released 25 Dec 2025 [^ruby4] and is at 4.0.7 as of this writing [^ruby407].

- **Nokogiri** ships native gems for Ruby 4.0 [^nokogiri-changelog] [^nokogiri-releases]; security defaults unchanged.
- **REXML** keeps accumulating CVEs: DoS via multiple XML declarations (CVE-2025-58767, fixed in 3.4.2+) [^cve-58767] [^ghsa-rexml], ReDoS via many digits (CVE-2024-49761, fixed in 3.3.9+) [^cve-49761]. It is patched case by case rather than hardened.
- **Ox, Oga, LibXML-Ruby:** no material changes relevant to Ruby 4.

---

## 3. What SAML requires of a parser

### XPath with namespace bindings

XML-DSIG verification in SAML needs XPath at several mandatory steps [^github-blog]:

- locating `<ds:Signature>`: `//ds:Signature` with `ds` bound to the DSIG namespace
- locating the signed reference: `./ds:Reference`
- locating the signed element by ID: `//*[@ID=$id]`

These are how an implementation determines *which* element was signed. Without XPath there is no XML-DSIG.

### Namespaces

SAML assertions are defined in terms of XML namespaces [^saml-core]. A `<saml:Audience>` is only valid when `saml` maps to `urn:oasis:names:tc:SAML:2.0:assertion` [^scalekit]; a namespace-blind parser can be fooled by a same-named element in another namespace. Exclusive XML Canonicalization operates on XPath node-sets that explicitly include or exclude namespace nodes [^exc-c14n]; getting it wrong breaks signatures or makes them forgeable.

### One parser, used everywhere

CVE-2025-25291 and CVE-2025-25292 (CVSS 8.8) in ruby-saml came from using **two parsers at once**: REXML for some XPath lookups, Nokogiri for canonicalization [^github-blog] [^csn]:

1. REXML sees signature A; Nokogiri canonicalizes assertion B.
2. The attacker crafts XML on which REXML and Nokogiri disagree about structure.
3. A valid signature over a low-privilege assertion verifies against a forged admin assertion.

The fix was incomplete: CVE-2025-66567 (Dec 2025) showed the two-parser architecture remained exploitable [^workos].

**Requirement:** one parser throughout, capable of namespace-aware XPath and exc-c14n.

---

## 4. Candidate evaluation

### Ox: unusable

| SAML requirement | Ox |
|---|---|
| XPath element location (`//ds:Signature`) | No |
| Namespace-aware element validation | No |
| Exclusive XML Canonicalization | No |
| XML-DSIG verification | No |

Using Ox would mean reimplementing XPath and a namespace-aware data model on top of it, which is reinventing Nokogiri.

### Oga: unusable

| Capability | Status |
|---|---|
| XPath 1.0 | Yes [^oga] |
| Namespace-aware XPath | Yes [^oga] |
| XML Canonicalization | Not implemented |
| Maintenance | Author states time is very limited [^oga] |

No C14N means no XML-DSIG, which means no SAML.

### LibXML-Ruby: viable, no advantage

| Capability | Status |
|---|---|
| XPath with namespace bindings | Yes [^libxml-ns] |
| C14N / exc-c14n | Yes, `Document#canonicalize`; W3C C14N tests pass [^libxml-changelog] |
| Ruby 4.0 | Supported without code changes [^libxml-changelog] |
| Maintenance | Active; v6.0.0 released Apr 2026 [^libxml-changelog] |

It wraps the same libxml2 as Nokogiri. CVE-2025-66568 (the "void canonicalization" attack) exploited libxml2 silently returning an empty string when canonicalization hits an invalid namespace URI instead of raising [^fragile-lock]. LibXML-Ruby is exposed to exactly the same behavior and would need the same guard ruby-saml 1.18.0 added: explicitly reject empty C14N output.

### Summary

| Parser | XPath + NS | C14N | libxml2 void-C14N exposure | Verdict |
|---|---|---|---|---|
| **Nokogiri** | Yes | Yes | Yes, must guard | Use it; guard against empty C14N output |
| **LibXML-Ruby** | Yes | Yes | Yes, same libxml2 | Viable, but same risk and worse ergonomics |
| **Oga** | Yes | No | n/a | Unusable for SAML |
| **Ox** | No | No | n/a | Unusable for SAML |
| **REXML** | Yes | No | n/a | Unsafe on untrusted input; source of the parser-differential CVEs |

---

## 5. Implications for this repository

ruby-saml2 already builds XML with Nokogiri and performs XML security through `nokogiri-xmlsec-instructure`, so it follows the single-parser architecture. Rules to keep it that way:

- Parse once with Nokogiri, with `strict.nonet`; never enable `NOENT`, `DTDLOAD`, or `DTDVALID`.
- Use Nokogiri XPath with explicit namespace bindings for every element lookup.
- Use Nokogiri/libxmlsec canonicalization only, and treat empty canonicalized output as a verification failure.
- Never introduce REXML, Ox, or Oga into any code path that touches a SAML message.

---

## References

[^xxe-page]: [Ruby XXE Prevention | XXE.page](https://xxe.page/guide/ruby/prevention)
[^safeguard]: [XXE Prevention in Ruby: Nokogiri NONET & NOENT Explained](https://safeguard.sh/resources/blog/xxe-prevention-in-ruby-with-nokogiri-nonetnoent)
[^codeql]: [XML external entity expansion — CodeQL query help](https://codeql.github.com/codeql-query-help/ruby/rb-xxe/)
[^ruby4]: [Ruby 4.0 released – but its best new features are not production ready (DevClass)](https://www.devclass.com/development/2026/01/06/ruby-40-released-but-its-best-new-features-are-not-production-ready/4079592)
[^ruby407]: [Ruby 4.0.7 Released](https://www.ruby-lang.org/en/news/2026/09/15/ruby-4-0-7-released/)
[^nokogiri-changelog]: [Nokogiri Changelog](https://nokogiri.org/CHANGELOG.html)
[^nokogiri-releases]: [Releases · sparklemotion/nokogiri](https://github.com/sparklemotion/nokogiri/releases)
[^cve-58767]: [CVE-2025-58767: DoS vulnerability in REXML](https://www.ruby-lang.org/en/news/2025/09/18/dos-rexml-cve-2025-58767/)
[^ghsa-rexml]: [GHSA-c2f4-jgmc-q2r5: DoS condition when parsing malformed XML file](https://github.com/ruby/rexml/security/advisories/GHSA-c2f4-jgmc-q2r5)
[^cve-49761]: [NVD CVE-2024-49761](https://nvd.nist.gov/vuln/detail/CVE-2024-49761)
[^github-blog]: [Sign in as anyone: Bypassing SAML SSO authentication with parser differentials (GitHub Blog)](https://github.blog/security/sign-in-as-anyone-bypassing-saml-sso-authentication-with-parser-differentials/)
[^saml-core]: [Assertions and Protocols for the OASIS SAML V2.0](https://docs.oasis-open.org/security/saml/v2.0/saml-core-2.0-os.pdf)
[^scalekit]: [Strengthening SAML Security with XML & XPath Validation (Scalekit)](https://www.scalekit.com/blog/xml-validation-in-saml)
[^exc-c14n]: [Exclusive XML Canonicalization Version 1.0 (W3C)](https://www.w3.org/TR/xml-exc-c14n/)
[^csn]: [Critical ruby-saml Vulnerabilities Let Attackers Bypass Authentication](https://cybersecuritynews.com/ruby-saml-vulnerabilities-bypass-authentication/)
[^workos]: [SAML's rough quarter: Five critical vulnerabilities (WorkOS)](https://workos.com/blog/saml-vulnerabilities-2026)
[^oga]: [yorickpeterse/oga](https://github.com/yorickpeterse/oga)
[^libxml-ns]: [XPath and Namespaces — libxml-ruby](https://xml4r.github.io/libxml-ruby/xpath/namespaces/)
[^libxml-changelog]: [Changelog — libxml-ruby](https://xml4r.github.io/libxml-ruby/changelog/)
[^fragile-lock]: [The Fragile Lock: Novel Bypasses for SAML Authentication (PortSwigger Research)](https://portswigger.net/research/the-fragile-lock)
