"""Rendered ownership boundaries, not just text/content assertions."""
import os
from pathlib import Path
import unittest
from playwright.sync_api import sync_playwright

URL = os.environ.get('DECK_URL', (Path(__file__).parents[1] / 'index.html').as_uri())


class SemanticGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()

    def assert_inside(self, inner, outer, padding=2):
        self.assertGreaterEqual(inner['x'], outer['x'] + padding)
        self.assertGreaterEqual(inner['y'], outer['y'] + padding)
        self.assertLessEqual(inner['x'] + inner['width'], outer['x'] + outer['width'] - padding)
        self.assertLessEqual(inner['y'] + inner['height'], outer['y'] + outer['height'] - padding)

    def assert_separate(self, a, b):
        self.assertTrue(a['x'] + a['width'] <= b['x'] or b['x'] + b['width'] <= a['x'] or
                        a['y'] + a['height'] <= b['y'] or b['y'] + b['height'] <= a['y'])

    def test_regional_services_and_subnet_geometry(self):
        for width, height in [(1920, 1080), (1366, 768), (1280, 720)]:
            with self.subTest(viewport=width):
                page = self.browser.new_page(viewport={'width': width, 'height': height}, reduced_motion='reduce')
                try:
                    page.goto(URL + '#architecture')
                    def box(selector):
                        return page.locator(selector).bounding_box()
                    vpc = box('#arch-vpc')
                    ops = box('#arch-ops-layer')
                    self.assert_separate(vpc, ops)
                    for service in ['#arch-ecr', '#arch-cloudwatch']:
                        self.assert_inside(box(service), ops)
                        self.assert_separate(box(service), vpc)
                        self.assertIn('ops', page.locator(service).get_attribute('class'))
                    for zone in ['#arch-public-zone', '#arch-app-zone', '#arch-data-zone', '#arch-access-zone']:
                        self.assert_inside(box(zone), vpc)
                    self.assert_inside(box('#arch-endpoints'), box('#arch-access-zone'))
                    for zone in ['#arch-public-zone', '#arch-app-zone', '#arch-data-zone']:
                        self.assert_separate(box('#arch-endpoints'), box(zone))
                    for service in ['#arch-web', '#arch-worker', '#arch-scheduler']:
                        self.assert_inside(box(service), box('#arch-app-zone'))
                    for service in ['#arch-postgresql', '#arch-redis']:
                        self.assert_inside(box(service), box('#arch-data-zone'))
                    self.assert_separate(box('#arch-dependency-key'), vpc)
                finally:
                    page.close()

    def test_ownership_and_identity_geometry(self):
        for width, height in [(1920, 1080), (1366, 768), (1280, 720)]:
            with self.subTest(viewport=width):
                page = self.browser.new_page(viewport={'width': width, 'height': height}, reduced_motion='reduce')
                try:
                    page.goto(URL + '#iac')
                    runtime = page.locator('.iac-layers').bounding_box()
                    bootstrap = page.locator('.bootstrap-boundary').bounding_box()
                    self.assert_separate(runtime, bootstrap)
                    self.assertEqual(page.locator('.iac-layers .bootstrap-boundary').count(), 0)
                    for layer in page.locator('.iac-layers .layer').all():
                        self.assert_inside(layer.bounding_box(), runtime)
                    result = page.locator('.loop-return').bounding_box()
                    for node in page.locator('.loop-node').all():
                        self.assert_separate(result, node.bounding_box())
                    page.goto(URL + '#security')
                    sso = page.locator('.human-sso')
                    self.assert_inside(sso.bounding_box(), page.locator('.human-lane').bounding_box())
                    self.assertEqual(sso.evaluate('(e) => getComputedStyle(e).borderTopStyle'), 'dashed')
                    self.assertIn('External to repository evidence', sso.inner_text())
                    self.assert_separate(sso.bounding_box(), page.locator('.automation-lane').bounding_box())
                    page.goto(URL + '#understand')
                    self.assertIn('SERVICE INVENTORY', page.locator('.compose-title').inner_text())
                    self.assertEqual(page.locator('.compose-system .service-card').count(), 6)
                    self.assertEqual(page.locator('.compose-system .flow-arrow').count(), 0)
                    for card in page.locator('.compose-system .service-card').all():
                        self.assert_inside(card.bounding_box(), page.locator('.compose-system').bounding_box())
                finally:
                    page.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
