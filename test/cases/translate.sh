#!/bin/bash

psql -U postgres test -c "select google_translate.translate('en', 'ru', 'hello world');"
