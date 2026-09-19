using '../main.bicep'

param environment = 'prod'
param alertEmail = 'sre-oncall@CHANGE-ME.com'
param failedRequestPercentThreshold = 5
param exceptionCountThreshold = 20
param severity = 1
