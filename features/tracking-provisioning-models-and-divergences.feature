Feature: Tracking prototypes and divergences
  In order to understand how all our instances are configured without locking ourselves into a static set of deployment options
  As a sysadmin
  I want to track our prototypes separately from how each instance diverges

  Scenario: Modifying a prototype
    Given the app-production instance is based on the rails-with-database prototype
    When I modify the rails-with-database prototype
    Then the diff between app-production and its prototype changes
    But the app-production instance itself is unaffected

  Scenario: Rebasing an instance onto a new prototype
    Given the app-production instance is based on the rails-with-database prototype
    And I've created a new hyrax prototype
    When I base app-production on hyrax instead of rails-with-database
    Then app-production's diff is against hyrax instead of rails-with-database
    But the app-production instance itself is unaffected
