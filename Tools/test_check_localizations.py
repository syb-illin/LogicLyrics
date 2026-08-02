import importlib.util
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).with_name("check_localizations.py")
SPEC = importlib.util.spec_from_file_location("check_localizations", MODULE_PATH)
assert SPEC and SPEC.loader
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class LocalizationValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.sources = self.root / "LogicLyrics"
        self.sources.mkdir()
        self.english = self.root / "en.strings"
        self.french = self.root / "fr.strings"

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_catalogs(self, english: str, french: str) -> None:
        self.english.write_text(english, encoding="utf-8")
        self.french.write_text(french, encoding="utf-8")

    def test_accepts_explicit_localization_present_in_both_catalogs(self) -> None:
        self.write_catalogs('"Hello" = "Hello";\n', '"Hello" = "Bonjour";\n')
        (self.sources / "View.swift").write_text(
            'Text(L10n.text("Hello"))\n', encoding="utf-8"
        )

        self.assertEqual(CHECKER.validate(self.sources, [self.english, self.french]), [])

    def test_rejects_static_ui_literal_and_missing_explicit_key(self) -> None:
        self.write_catalogs('"Hello" = "Hello";\n', '"Hello" = "Bonjour";\n')
        (self.sources / "View.swift").write_text(
            'Text("Untracked")\nText(L10n.text("Missing"))\n', encoding="utf-8"
        )

        issues = CHECKER.validate(self.sources, [self.english, self.french])

        self.assertTrue(any("static UI copy must use L10n" in issue for issue in issues))
        self.assertTrue(any("missing localization key: 'Missing'" in issue for issue in issues))

    def test_rejects_words_around_interpolation_but_accepts_data_only_text(self) -> None:
        self.write_catalogs('"Hello" = "Hello";\n', '"Hello" = "Bonjour";\n')
        (self.sources / "View.swift").write_text(
            'Text("v\\(version) · build \\(build)")\nText("\\(count)")\n',
            encoding="utf-8",
        )

        issues = CHECKER.validate(self.sources, [self.english, self.french])

        self.assertEqual(len(issues), 1)
        self.assertIn("build", issues[0])

    def test_rejects_catalog_parity_duplicates_and_empty_translations(self) -> None:
        self.write_catalogs(
            '"Hello" = "Hello";\n"Hello" = "Again";\n"Empty" = "";\n',
            '"Hello" = "Bonjour";\n"French only" = "Français";\n',
        )
        (self.sources / "View.swift").write_text("", encoding="utf-8")

        issues = CHECKER.validate(self.sources, [self.english, self.french])

        self.assertTrue(any("duplicate key: 'Hello'" in issue for issue in issues))
        self.assertTrue(any("empty translation: 'Empty'" in issue for issue in issues))
        self.assertTrue(any("key missing from this catalog: 'Empty'" in issue for issue in issues))
        self.assertTrue(any("key missing from this catalog: 'French only'" in issue for issue in issues))


if __name__ == "__main__":
    unittest.main()
