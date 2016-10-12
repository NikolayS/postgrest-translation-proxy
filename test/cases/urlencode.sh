#!/bin/bash

psql -U postgres test -c "select google_translate.urlencode('hello world');"
