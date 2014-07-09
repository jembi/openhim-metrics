Metrics Service

This service accepts a json payload containing timing data for an operation.

It writes this data to 'time slices' in mongodb. These are hard-coded to 5 seconds at present but should be made configurable.

Data is then served to clients (a graph) in a standard format.


