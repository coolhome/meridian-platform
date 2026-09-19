using '../main.bicep'

param environment = 'dev'
param alertEmail = 'sre-dev@CHANGE-ME.com'
param failedRequestPercentThreshold = 20
param exceptionCountThreshold = 100
param severity = 3
