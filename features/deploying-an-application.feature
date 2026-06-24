Feature: Deploying an application
  Developers are the primary people responsible for deploying a released
  version of an application to the hosting environment. Updating an
  application is a common task, and so, should be convenient and
  expected to succeed. Developers should be notified if something goes
  wrong and be able to inspect the details. Otherwise, deploying
  software should largely be an uninteresting event.

  In order to deliver new features to my stakeholders and end-users
  As an application-oriented developer
  I want to release a new version of my application

  Background:
    Given hosting for my application is provisioned
    And I am a developer authorized to deploy this application
    And I have a release of my application

  Scenario: Notifying developers when deployment fails
    Given I have deployed my release
    When my release fails to deploy
    And the deployment failure is because of a problem with my release
    Then I am notified that my release could not be deployed

  Scenario: Checking status after deployment succeeds
    Given I have deployed my release
    And my release successfully launches
    When I check my application status
    Then I can see that my release has launched

  Scenario: Monitoring deployment status
    Given a deployment is active
    When I check my application status
    Then I can see the deployment's current state
