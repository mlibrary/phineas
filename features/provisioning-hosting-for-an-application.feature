Feature: Provisioning hosting for an application
  In order to allow developers to deploy an application
  As a sysadmin
  I want to provision hosting for that application

  Background:
    Given an application team wants a new instance of their application
    And I am a sysadmin authorized to provision new instances

  Scenario: Provisioning an instance of an application for the first time
    Given no instances of this application are provisioned

  Scenario: Provisioning an instance of an already provisioned application
    Given an instance of this application is already provisioned
