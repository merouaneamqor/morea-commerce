import io
import json
import unittest
from unittest.mock import Mock, patch

from store_report import NoRedirect, report


class ReportTests(unittest.TestCase):
    def response(self, payload):
        response = io.StringIO(json.dumps(payload))
        response.url = 'https://store.example/graphql'
        return response

    @patch('store_report.build_opener')
    def test_authenticated_read_only_query(self, opener):
        opener.return_value.open.return_value = self.response({'data': {'stats': {'placedCount': 2}}})
        result = report('https://store.example/graphql', 'test-token')
        request = opener.return_value.open.call_args.args[0]
        self.assertEqual(request.get_header('Authorization'), 'Bearer test-token')
        self.assertTrue(json.loads(request.data)['query'].startswith('query'))
        self.assertEqual(result['stats']['placedCount'], 2)

    @patch('store_report.build_opener')
    def test_graphql_errors_fail_instead_of_publishing_partial_report(self, opener):
        opener.return_value.open.return_value = self.response({'data': {'stats': None}, 'errors': [{'message': 'private'}]})
        with self.assertRaisesRegex(RuntimeError, 'query failed'):
            report('https://store.example/graphql', 'test-token')

    @patch('store_report.build_opener')
    def test_plain_http_rejected_before_sending_token(self, opener):
        with self.assertRaises(ValueError):
            report('http://store.example/graphql', 'test-token')
        opener.assert_not_called()

    def test_redirect_rejected_before_forwarding_credentials(self):
        with self.assertRaisesRegex(ValueError, 'redirects'):
            NoRedirect().redirect_request(Mock(), None, 302, '', {}, 'https://other.example')


if __name__ == '__main__':
    unittest.main()
