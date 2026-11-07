Field Station Network: Data Handbook
=====================================

This handbook describes how the field station network collects,
checks and archives its daily weather readings. Each station sends
one reading every ten minutes. A reading holds the air temperature,
the relative humidity, the air pressure, the wind speed and the
wind direction. The central server stores every reading in a plain
text log, and once a day the logs are packed into a single archive
file together with the station list and this handbook.

1. Stations

Every station has a short identifier such as ST042, a name, a region
and its position. The position is given as latitude and longitude in
degrees and as the elevation above sea level in metres. A station is
either active, under maintenance or retired. Retired stations are kept
in the list so that old readings can still be matched to a place.

2. Readings

A reading is accepted when all five values lie inside their valid
ranges and the time stamp is not older than the previous reading of
the same station. A reading that fails one of these checks is kept in
the log, but it is marked as rejected and it is not used for the daily
summary. When a station sends no reading for more than one hour, the
server writes a warning to the log and sends a message to the station
keeper. When the station comes back, the server writes a notice.

3. Daily summary

For every active station the server computes the lowest, the highest
and the mean temperature of the day, the total rain and the strongest
wind gust. The summary is written to the log at midnight and it is
sent to the regional offices in the morning.

4. Archive

The daily archive must be small, because some regional offices still
receive it over slow radio links. Text files compress well, but no
single method is best for every file: short notes are often best left
as they are, long tables with repeated words favour dictionary methods,
and logs with many similar lines favour methods that copy earlier text.
The archiver therefore tries every method on every file and keeps the
smallest result. Each entry of the archive records the method, the
original size, the compressed size and a checksum of the original
text, so that the receiving office can check that nothing was lost
on the way.

5. Contact

Questions about the network go to the operations desk. Questions about
a single station go to its keeper, whose name is listed in the station
file.
