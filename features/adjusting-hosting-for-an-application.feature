Feature: Adjusting hosting for an application
  In order to improve the experience of my end-users
  As an infrastructure-oriented developer
  I want to modify the hosting details of my application

  Scenario: Modifying my application instance
    Given an instance of my application is already running
    And I am a developer authorized to modify the application instance's infrastructure
    When I add a new persistent volume mount
    Then my application is redeployed
    And my new volume mount is in place

  Scenario:
    Given several instances of my application are running
    And I am a developer authorized to view details about my application
    When I check the configurations for my application's instances
    Then I can see individual configurations
    And I can see how any configurations differ from any other
