# HelloID-Conn-Prov-Target-Planon-Persons
| :warning: Warning |
|:---------------------------|
Planon uses an API which needs to be configured for each customer by a Planon consultant. Therefore this connector will **not work** out of the box without assistance from a Planon consultant and HelloID consultant.

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.tools4ever.nl/wp-content/webp-express/webp-images/uploads/2024/07/HelloID-Conn-Prov-Target-Planon-Order-300x80.png.webp">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Planon-Persons](#helloid-conn-prov-target-connectorname)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Available lifecycle actions](#available-lifecycle-actions)
    - [Field mapping](#field-mapping)
  - [Remarks](#remarks)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Planon-Persons_ is a _target_ connector. _Planon-Persons_ provides a set of REST API's that allow you to programmatically interact with its data.

## Getting started

### Prerequisites
- Connection settings

### Connection settings

The following settings are required to connect to the API.

| Setting           | Description                                       | Mandatory |
| ----------------- | ------------------------------------------------- | --------- |
| AuthUrl         | The URL to the API for requesting token              | Yes       |
| BaseUrl           | The URL to the API                                | Yes       |
| ClientID           | ClientID to connect to the API                                | Yes       |
| ClientSecret           | ClientSecret to connect to the API                                | Yes       |
| RenameResources   | When enabled, rename departments and functions    | Yes       |


### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Planon-Persons_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `Code`                            |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

## Supported  features

The following features are available:

| Feature                                   | Supported | Actions                         | Remarks                                                      |
| ----------------------------------------- | --------- | ------------------------------- | ------------------------------------------------------------ |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable | There is no Delete action, the disable acts as a soft delete |
| **Permissions**                           | ❌         | Retrieve, Grant, Revoke         | Static or Dynamic                                            |
| **Resources**                             | ✅         | Create departments and functions                               |                                                              |
| **Entitlement Import: Accounts**          | ✅         | -                               |                                                              |
| **Entitlement Import: Permissions**       | ✅         | -                               |                                                              |
| **Governance Reconciliation Resolutions** | ❌        | -                               |                                                              |

### Fieldmapping

The field mapping can be imported by using the _fieldMapping.json_ file. Please be aware of the fact that the default fieldmapping will not meet your requirements delivered by Planon. This is custom work at the Planon site. 

There are 3 properties (DepartmentRef, RefBOStateUserDefined and CostCentreRef) that need to have a dollar sign in front of them when creating or updating a person. However this is not possible in the fieldmapping, therefore the create and update scripts replace these properties in the actioncontext.data or correlatedAccount respectively.

The property FreeString41 gets populated with the reference of the manager in the create and update scripts. This is an optional option. Pleas enable this code on line 118 if neccecary.

## Remarks

All the requests to the api are a POST even the ones that only retrieve information.

### Resource scrips
The connector makes use of two resource scripts to create the necessary functions and departments in the target system before the user gets created.

In these resource scripts, there is a GET call used to retrieve the functions and departments, but it requires an empty object to be sent in the request body, which appears somewhat unusual in the code.

The department resource script requires two value's a displayname and externalid. For example _Department_.

The function resource script requires two value's a name and externalid. For example _Title_.

### Get user call

The get call to retrieve users is a POST request. The request uses a filter in the body to retrieve the user based on Code

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint                           | Description                     |
| ---------------------------------- | ------------------------------- |
| /read/HelloIDAPI                   | Retrieve person information     |
| /execute/HelloIDAPI/BomAdd         | Create person                   |
| /update/HelloIDAPI                 | Update person                   |
| /read/HelloIDAPIEenheden           | Retrieve department information |
| /execute/HelloIDAPIEenheden/BomAdd | Create departments              |
| /read/HelloIDAPIFuncties           | Retrieve function information   |
| /execute/HelloIDAPIFuncties/BomAdd | Create functions                |


## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/5289-helloid-conn-prov-target-planon-persons)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
