#!/bin/bash

psql -U postgres test -c "select google_translate.translate('WRONG_KEY', 'en', 'ru', 'hello world again');"
