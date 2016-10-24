#!/bin/bash

psql -U postgres test -c "select v1.google_translate('ru', 'en', string_agg(char, '')) from (select chr(generate_series) as char from generate_series(1, 126)) as z"
