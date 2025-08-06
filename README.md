# README

# How to setup this project
You will need:
* Ruby version 3.3.4
* A Postgres database up and running

## Install the dependencies using
`bundle install`


## Tools to setup to get the app up and running


* Postgres
  - Setup For Mac OS Users:
    - One can use the related instructions [here](https://postgresapp.com/)
* Redis
  - For Mac OS Users:
    - Assuming you have homebrew already installed one can use `brew install redis` to setup Redis


## Create the database with the appropriate database schema

* Run from the project root directory: `rake db:create` and `rake db:migrate`

## Please add your Github personal token using Rails Credentials as per the below format

- **Add/Edit Github API token**: Please replace 'enviroment' in the below command with the actual environment among 'production', 'development', 'test' enviroment to setup/update Rails credentials in the respective enviroment accordingly.

`EDITOR="code --wait" bin/rails credentials:edit --environment 'enviroment'`

- How these credentials are accessed in the Rails app: `Rails.application.credentials.github.api_token`(used in: `GithubSync::GithubClient` related class)

- How to specify your credentials in the appropriate 'filename-enviroment.yml'

Please replace 'Please Insert Your Github API Token here' with your actual Github API token.

```
github:
  api_token: 'Please Insert Your Github API Token here'

```



## Running the Rails app server and other required tools
- **Postgres**: Make sure you have Postgres DB Server is Running(with [Postgres.app](https://postgresapp.com/) it is configured to automatically run on your local machine once the system boots/starts)
- **Redis**: Run Redis in background with: `brew services start redis`(You can check if Redis is running with: `brew services info redis`)
- **Start Rails app server**: Run application server with: `rails server`
- **Run Sidekiq in Background**: In a separate terminal run the required Sidekiq Background job processor with: `bundle exec sidekiq -q github_issues`


## In order to Sync the Storyblok Github Issues & Persist them to local DB in order to filter by Open & Closed issues, one can use the following command once the app is up and running

- `curl "http://localhost:3000/api/v1/repos/github/storyblok/storyblok/issues"``

  - Please note the above command assumes your Rails app server is running on port 3000

## High level overview of how the App related Issues API works for Syncing & Filtering


### Default API filtering Behavior

### Get Issues API Defaults

- The default sorting state when no explicit `state` filter is specified in the API call is sort the issues by `open` issue state
- The Issues API fetches the issues sorted by `issue_created_at` which corresponds to the timestamp of when the issue was created at on the Github platform
- The sorting order is sort by Issues `DESC`

### Initial Sync Behavior
- In the Initial sync to the Issues API using the above link, an API call is made to Github to return the top 25 open issues(uses configured set `Pagy` default limit) in the API response and in the background a job is triggerred to save all the open & closed issues to the DB
  - **Pease note:** In the case of Storyblok, `curl "http://localhost:3000/api/v1/repos/github/storyblok/storyblok/issues"` returns an empty array because we don't have any existing open issues currently on the Storyblok repo


### Incremental Sync Behavior
- In subsequent Issues API calls to an already initially synced repo, an Incremental Sync is triggered in the background that retrieves all newly created issues & updated Github issues using the Github List Issue API's `since` timestamp for more efficient processing and while this `upsert` happens in the background for newly created and recently updated Github repo issues based on the databases most recent record related Github `issue_updated_at` timestamp corresponding to that Github repo, it simultaneously also fetches existing issues from the DB as part of the API response based on the filter options specified as part of the original API call made

### Different API calls that trigger the Initial/Incremental Sync

#### When No specific filter state is specified
- curl "http://localhost:3000/api/v1/repos/github/boddhisattva/ruby_test_task/issues?"

#### When an explicit filter by `open` state is specified
- curl "http://localhost:3000/api/v1/repos/github/boddhisattva/ruby_test_task/issues?state=open"

#### When an explicit filter by `closed` state is specified
- curl "http://localhost:3000/api/v1/repos/github/boddhisattva/ruby_test_task/issues?state=closed"


## Running the test suite

* Please make sure you have the Github API token setup as per the above section
for the `test` environment before running the tests with the below command

`bundle exec rspec`

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

## Please note: Security related app updates
- Given Rails version of app is 7.1.3.4, currently I've updated the app based on Dependabot alerts & the related gems on Github to handle various levels of severity and handle various security vulnerabilities.
