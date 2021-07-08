# README

# How to setup this project
You will need:
* Ruby version 3.3.4
* A Postgres database up and running

## Install the dependencies using
`bundle install`

## Create the databases on your database server

backend_test_development

backend_test_test

Export the database credentials using environment variable or just edit the database.yml

## Running the test suite
`bundle exec rspec`

## Running the server
`rails server`
