# Cozy Monitor

Cozy Monitor is a tool to manage your Cozy Platform from the command line.

## Install

Install it via NPM

    npm install cozy-monitor -g

## Features

Run following command to see all available actions:

    cozy-monitor --help

Or browse the online
[documentation](http://cozy.io/host/manage.html##applications-management).

## Contribution

You can contribute to Cozy Monitor in many ways:

* Pick up an [issue](https://github.com/cozy/cozy-monitor/issues?state=open) and solve it.
* Improve displayed messages.
* Write tests.

## Hack

Get sources:

    git clone https://github.com/cozy/cozy-monitor.git

Run:

    cd cozy-monitor
    chmod +x bin/cozy-monitor
    ./bin/cozy-monitor

Each modification requires a new build, here is how to run a build:

    npm run build

Make sure your modifications pass linting:

    npm run lint

## Tests

![Build
Status](https://travis-ci.org/cozy/cozy-monitor.png?branch=master)

To run tests type the following command into the Cozy Home folder:

    npm run test

## License

Cozy Monitor is developed by Cozy Cloud and distributed under the LGPL v3 license.

## What is Cozy?

![Cozy Logo](https://raw.github.com/cozy/cozy-setup/gh-pages/assets/images/happycloud.png)

[Cozy](http://cozy.io) is a platform that brings all your web services in the
same private space.  With it, your web apps and your devices can share data
easily, providing you with a new experience. You can install Cozy on your own
hardware where no one profiles you.

## Community

You can reach the Cozy Community by:

* Chatting with us on IRC #cozycloud on irc.freenode.net
* Posting on our [Forum](https://forum.cozy.io)
* Posting issues on the [Github repos](https://github.com/cozy/)
* Mentioning us on [Twitter](http://twitter.com/mycozycloud)
