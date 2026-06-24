Feature: Provisioning hosting for an application
  In order to allow developers to deploy an application
  As a sysadmin
  I want to provision hosting for that application

  Background:
    Given an application team wants a new testing instance of their foo application
    And I am a sysadmin authorized to provision new instances

  Scenario:
    Given no instances of foo are provisioned
    When I check for existing configurations of foo
    Then I can see that there are none

  Scenario:
    Given foo-demo, foo-staging, and foo-production are already provisioned
    When I check for existing configurations of foo
    Then I can see the differences and similarities between the existing instances of foo

  Scenario:
    Given I have provisioned an instance called foo-development
    And it is based on the rails prototype
    When I check the configuration of foo-development
    Then I can see that foo-development is based on our rails prototype
    And its configuration does not differ from its prototype's
