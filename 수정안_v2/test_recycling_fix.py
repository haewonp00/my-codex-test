"""Small regression tests: coordinates are in-memory examples, not fabricated dataset files."""
import argparse
import contextlib
import io
import unittest
from unittest import mock
import recycling_fix as rf


class ValidationTests(unittest.TestCase):
    def test_mapping_list_and_dict(self):
        self.assertEqual(rf.normalize_names(['plastic','paper','metal']), rf.NAMES)
        self.assertEqual(rf.normalize_names({'0':'plastic','1':'paper','2':'metal'}), rf.NAMES)

    def test_empty_background_label(self):
        self.assertEqual(rf.parse_labels(' \n\n'), [])

    def test_invalid_rows_fail(self):
        for text in ['3 .5 .5 .2 .2', '0.5 .5 .5 .2 .2', '0 nan .5 .2 .2',
                     '0 .5 .5 0 .2', '0 .95 .5 .2 .2', '0 .5 .5 .2']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                rf.parse_labels(text)

    def test_touching_boundary_is_valid(self):
        self.assertEqual(len(rf.parse_labels('0 .5 .5 1 1')),1)

    def test_containment_is_review_candidate_not_automatic_merge(self):
        rows=rf.parse_labels('0 .5 .5 .8 .8\n0 .5 .8 .2 .1')
        containment, ratio=rf.overlap(*rows)
        self.assertAlmostEqual(containment,1)
        self.assertLess(ratio,.6)
        self.assertEqual(len(rows),2)

    def test_separate_boxes_not_contained(self):
        self.assertEqual(rf.overlap((0,.1,.1,.1,.1),(0,.8,.8,.1,.1))[0],0)

    def test_default_training_plan_does_not_initialize_model(self):
        args=argparse.Namespace(data='reviewed_data.yaml',pretrained='MISSING.pt',
              out='new_run',device='0',reviewed=False,execute=False)
        with mock.patch.object(rf,'inspect_dataset',return_value=({},[])), \
             mock.patch.object(rf,'load_pretrained') as load, contextlib.redirect_stdout(io.StringIO()):
            rf.training_plan(args)
        load.assert_not_called()

    def test_training_requires_review_confirmation(self):
        args=argparse.Namespace(data='reviewed_data.yaml',pretrained='MISSING.pt',
              out='new_run',device='0',reviewed=False,execute=True)
        with mock.patch.object(rf,'inspect_dataset',return_value=({},[])), \
             mock.patch.object(rf,'load_pretrained') as load, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(ValueError): rf.training_plan(args)
        load.assert_not_called()

    def test_model_loading_requires_real_weights(self):
        with self.assertRaises(FileNotFoundError): rf.load_model('/tmp/this_model_was_not_supplied.pt')


if __name__=='__main__':
    unittest.main()
