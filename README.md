# PTSKIM

A frequency based transit [skimming](https://tfresource.org/topics/Skim_Matrix.html) and [assignment](https://tfresource.org/topics/Network_assignment.html) model, based on the article:

Gentile, G., Nguyen, S., Pallottino, S. (2005). Route choice on transit networks with online information at stops. Transportation Science 39 (3), 289–297

for the case of deterministic headways.

The model allows for strict capacity constraints and crowding modelling according to the article:

Wardman, M., G.A. Whelan (2011). 20 Years or railway crowding valuation studies: evidence and lessons from British experience.Transport Reviews, 31, 379-398.

PTSKIM is a console application that reads its settings from a [control file](https://github.com/transportmodelling/PTSKIM/wiki/Control-file) that is passed as a command line argument.

# Dependencies
Before you can compile this program, you will need to clone the https://github.com/transportmodelling/Utils and https://github.com/transportmodelling/matio repositories, and then add it to your Delphi Library path.
