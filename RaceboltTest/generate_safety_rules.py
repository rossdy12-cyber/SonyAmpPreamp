#!/usr/bin/env python3
"""Generate separate WebKit-compatible filters; never use regex alternation."""
import json
from pathlib import Path


def make_rules():
    filters = []
    # A path segment boundary has three possibilities, expressed as THREE rules.
    # WebKit URLFilterParser rejects `|` even though NSRegularExpression accepts it.
    for segment in ['checkout', 'order-pay', 'order-received', 'pay-for-order', 'add-payment-method']:
        for boundary in ['/', '[?#]', '$']:
            filters.append(r'^https?://[^/]+/([^?#]*/)?' + segment + boundary)
    actions = ['checkout', 'place[-_]?order', 'process[-_]?payment', 'create[-_]?order',
               'approve[-_]?order', 'capture[-_]?order', 'payment[-_]?intent',
               'ppc[-_]', 'ppcp', 'stripe', 'wcpay']
    for key in ['wc-ajax', 'wc_ajax', 'action', 'rest_route']:
        for prefix in [r'[?&]', '%3f', '%26']:
            for separator in ['=', '%3d']:
                for action in actions:
                    filters.append(prefix + key + separator + '[^&#]*' + action)
    for host in ['paypal.com', 'paypalobjects.com', 'stripe.com', 'stripe.network',
                 'klarna.com', 'squareup.com', 'apple-pay-gateway.apple.com']:
        filters.append(r'^https?://([^/]+\.)?' + host.replace('.', r'\.') + '/')
    assert len(filters) == len(set(filters))
    assert all('|' not in f and '(?' not in f and f.isascii() for f in filters)
    return [{'trigger': {'url-filter': f, 'url-filter-is-case-sensitive': False},
             'action': {'type': 'block'}} for f in filters]


if __name__ == '__main__':
    path = Path(__file__).with_name('LiveSafetyRules.json')
    rules = make_rules()
    path.write_text(json.dumps(rules, indent=2) + '\n')
    print(f'Generated {len(rules)} separate WebKit-safe patterns: {path}')