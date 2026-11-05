---
layout: default
title: Changelog
description: What changed in each Kex release.
permalink: /changelog/
---

# Changelog

{% capture changelog %}{% include changelog.md %}{% endcapture %}
{{ changelog | markdownify }}
