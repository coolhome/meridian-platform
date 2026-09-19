using '../main.bicep'

param environment = 'test'
param alertEmail = 'sre-test@CHANGE-ME.com'
param failedRequestPercentThreshold = 10
param exceptionCountThreshold = 50
param severity = 2
