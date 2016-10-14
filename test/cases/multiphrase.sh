#!/bin/bash

psql -U postgres test -c "select google_translate.translate('en', 'ru', array['hello world', 'and hi again']);"
