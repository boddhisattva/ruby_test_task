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

## User Story
As a dev relations manager of Storyblok
I want to have an API endpoint from https://github.com/storyblok/storyblok/
So that I can see open and closed issues from that repository and filter by status

## Code Related Design Decisions & Performance Improvements
- The Code Has 2 Main Paths
  - Path 1: Initial Sync is to get all the issues in a repo end to end
  - Path 2: Incremental Sync to only get the newly created or latest updated issues and this is faster as it does avoid the end to end scan to get new or updated records
- Have made use of a counter caching strategy with a separate table related count in order to get the total number of issues present in the repo in the response header and this is done to avoid a full table scan to count total issues
- Various indexes have been added to improve performance where have to do querying, filtering or related DB lookups
- When Fetching Issues from DB have implemented a Fragment Cache for efficient issue look ups and this caching is also available per page
- Issues & Users are attempted to be inserted via Batch Processing as part of a BULK Upsert strategy and in batches of 5k issues at a time and this to limit the the number of DB Round trips and for better performance
- Also used headers like "Cache-Control" to allow Browsers, CDN's to store data for a given period of time for better performance
- Have set a Max number of items that be fetched as part of each API call to be max 100 to prevent misuse. This is configured in Pagy Configuration
- REST API Design has been implemented in such a way to support other providers in the future as needed other than 'Github'
- Made use of ETag for more efficient client side caching
- Have Implemented Eager loading and designed in the classes in a way to adhere to SOLID principles
- Use Sidekiq Jobs as well for Background Processing for better performance
- Added some Timeout options & configurations as well to Octokit(in their initializer) to add some guardrails for Network Timeouts


## Areas of Improvement
- Store the 5k accumulated users in Memcached instead of in memory as that is more performant and avoids using in memory store
- Add API documentation for the implemented API
- Specs can be improved & refactored further to use things like build_stubbed, build etc.,
- Add more Rate limiting enhancments based on customer needs to prevent misuse

## Testing Sample API calls
1. `curl "http://localhost:3000/api/v1/repos/github/microsoft/terminal/issues?state=closed"`
2. `curl "http://localhost:3000/api/v1/repos/github/boddhisattva/ruby_test_task/issues?state=open"`
3. `curl "http://localhost:3000/api/v1/repos/github/boddhisattva/ruby_test_task/issues?page=2&per_page=3&state=open"`
4.  `curl "http://localhost:3000/api/v1/repos/github/boddhisattva/ruby_test_task/issues?page=3&per_page=3&state=all"`
