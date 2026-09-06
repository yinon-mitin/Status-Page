"""Browser regression tests. Run with Python + Playwright; no deck build step."""
import os
from pathlib import Path
import unittest
from playwright.sync_api import sync_playwright

URL = os.environ.get('DECK_URL', (Path(__file__).parents[1] / 'index.html').as_uri())

class DeckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.playwright = sync_playwright().start()
        cls.browser = cls.playwright.chromium.launch()

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.playwright.stop()

    def setUp(self):
        self.page = self.browser.new_page(viewport={'width': 1280, 'height': 720}, reduced_motion='reduce')
        self.page.goto(URL + '#title')

    def tearDown(self):
        self.page.close()

    def slide(self):
        return self.page.locator('.slide.active').get_attribute('id')

    def test_complete_keyboard_rehearsal(self):
        p = self.page
        p.keyboard.press('ArrowRight')
        p.keyboard.press('n')
        p.keyboard.press('PageDown')
        self.assertEqual(self.slide(), 'method')
        self.assertIn('Project approach', p.locator('#notes-title').inner_text())
        p.keyboard.press('PageUp')
        self.assertEqual(self.slide(), 'challenge')
        p.keyboard.press('n')
        p.locator('#notes-toggle').click()
        p.keyboard.press('ArrowRight')
        self.assertEqual(self.slide(), 'method')
        p.locator('#notes-close').click()
        p.keyboard.press('?')
        self.assertTrue(p.locator('#help').is_visible())
        p.keyboard.press('Escape')
        self.assertFalse(p.locator('#help').is_visible())
        p.keyboard.press('f')
        p.wait_for_function('!!document.fullscreenElement')
        p.keyboard.press('ArrowRight')
        self.assertEqual(self.slide(), 'understand')
        p.keyboard.press('f')
        p.wait_for_function('!document.fullscreenElement')
        p.keyboard.press('Home')
        self.assertEqual(self.slide(), 'title')
        p.locator('body').click(position={'x': 640, 'y': 30})
        p.keyboard.press('Space')
        self.assertEqual(self.slide(), 'challenge')
        p.keyboard.press('End')
        self.assertEqual(self.slide(), 'closing')
        p.keyboard.press('Space')
        self.assertEqual(self.slide(), 'closing')
        p.locator('.appendix-entry').click()
        p.wait_for_function("document.querySelector('.slide.active').id==='appendix-platform'")
        p.keyboard.press('PageDown')
        self.assertEqual(self.slide(), 'appendix-ownership')
        p.keyboard.press('Home')
        self.assertEqual(self.slide(), 'appendix-platform')
        p.keyboard.press('Escape')
        self.assertEqual(self.slide(), 'closing')
        # A real PDF is checked by tools/qa_deck.py. Avoid a modal print dialog here.
        p.evaluate('window.print = () => { window.printRequested = true; }')
        p.keyboard.press('p')
        self.assertTrue(p.evaluate('window.printRequested'))
        self.assertEqual(p.evaluate('[scrollX, scrollY]'), [0, 0])

    def test_all_slides_in_main_and_appendix_flow(self):
        main = self.page.locator('.slide:not(.appendix-slide)').evaluate_all('ss=>ss.map(s=>s.id)')
        self.assertEqual(main, ['title','challenge','method','understand','why-ecs','architecture','iac','security','cicd','testing','recovery','idempotency','evidence','learnings','closing'])
        for sid in main[1:]:
            self.page.keyboard.press('ArrowRight')
            self.assertEqual(self.slide(), sid)
        self.page.locator('.appendix-entry').click()
        self.page.wait_for_function("document.querySelector('.slide.active').id==='appendix-platform'")
        for sid in ['appendix-ownership','appendix-network','appendix-release','appendix-sources']:
            self.page.keyboard.press('ArrowRight')
            self.assertEqual(self.slide(), sid)
        self.page.locator('#return-main').click()
        self.assertEqual(self.slide(), 'closing')
        self.page.keyboard.press('ArrowLeft')
        self.assertEqual(self.slide(), 'learnings')

    def test_native_buttons_and_link_focus(self):
        p = self.page
        p.locator('#notes-toggle').focus()
        p.keyboard.press('Enter')
        self.assertIn('notes-open', p.locator('body').get_attribute('class'))
        p.keyboard.press('Enter')
        self.assertNotIn('notes-open', p.locator('body').get_attribute('class') or '')
        p.locator('#title .repo-link').focus()
        with p.expect_popup() as popup:
            p.keyboard.press('Enter')
        tab = popup.value
        tab.wait_for_url('https://github.com/yinon-mitin/Status-Page')
        tab.close()
        p.bring_to_front()
        p.keyboard.press('ArrowRight')
        self.assertEqual(self.slide(), 'challenge')
        p.keyboard.press('Control+ArrowRight')
        self.assertEqual(self.slide(), 'challenge')
        p.locator('#help-toggle').click()
        p.keyboard.press('PageDown')
        self.assertEqual(self.slide(), 'method')
        p.locator('#help-close').click()
        p.keyboard.press('PageDown')
        self.assertEqual(self.slide(), 'understand')
        self.assertEqual(p.evaluate('[scrollX, scrollY]'), [0, 0])

    def test_progress_is_scoped_to_current_section(self):
        p = self.page
        bar = p.locator('#progress')
        bar.click(position={'x': 1278, 'y': 2})
        self.assertEqual(self.slide(), 'closing')
        p.locator('.appendix-entry').click()
        p.wait_for_function("document.querySelector('.slide.active').id==='appendix-platform'")
        bar.click(position={'x': 1278, 'y': 2})
        self.assertEqual(self.slide(), 'appendix-sources')
        self.assertEqual(p.locator('#slide-counter').text_content(), 'A 5/5')
        p.keyboard.press('End')
        self.assertEqual(self.slide(), 'closing')
        p.keyboard.press('Home')
        bar.focus()
        p.keyboard.press('Space')
        self.assertEqual(self.slide(), 'challenge')

    def test_notes_leave_slide_and_controls_visible(self):
        self.page.locator('#notes-toggle').click()
        self.page.wait_for_timeout(300)
        deck = self.page.locator('#deck').bounding_box()
        panel = self.page.locator('#notes-panel').bounding_box()
        self.assertLessEqual(deck['x'] + deck['width'], panel['x'])
        chrome = self.page.locator('#chrome').bounding_box()
        self.assertGreaterEqual(chrome['y'], panel['y'] + panel['height'])
        self.assertTrue(self.page.locator('#notes-close').is_visible())

    def test_main_talk_stops_before_appendix(self):
        last_main = self.page.locator('.slide:not(.appendix-slide)').last.get_attribute('id')
        self.page.keyboard.press('End')
        self.assertEqual(self.slide(), last_main)
        self.page.keyboard.press('ArrowRight')
        self.assertEqual(self.slide(), last_main)
        self.assertTrue(self.page.locator('#next-slide').is_disabled())
        self.page.evaluate("location.hash='appendix-platform'")
        self.page.wait_for_function("document.querySelector('.slide.active').id === 'appendix-platform'")
        self.page.keyboard.press('ArrowRight')
        self.assertEqual(self.slide(), 'appendix-ownership')
        self.page.keyboard.press('End')
        self.assertEqual(self.slide(), last_main)

    def test_arrows_work_after_notes_button_click(self):
        self.page.locator('#notes-toggle').click()
        self.page.keyboard.press('ArrowRight')
        self.assertEqual(self.slide(), 'challenge')
        self.assertIn('notes-open', self.page.locator('body').get_attribute('class'))
        self.page.keyboard.press('ArrowLeft')
        self.assertEqual(self.slide(), 'title')
        self.page.keyboard.press('Space')  # Native focused Notes button activation.
        self.assertNotIn('notes-open', self.page.locator('body').get_attribute('class') or '')
        self.assertEqual(self.slide(), 'title')

if __name__ == '__main__':
    unittest.main(verbosity=2)
