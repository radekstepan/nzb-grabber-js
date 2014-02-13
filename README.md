![image](https://raw.github.com/radekstepan/nzb-grabber-js/master/logo.png)

Download/grab binary posts from NNTP (Usenet) servers using Node.js.

[ ![Codeship Status for radekstepan/nzb-grabber-js](https://www.codeship.io/projects/a310f8d0-b344-0130-ecd7-6e1ddaa2b72b/status?branch=master)](https://www.codeship.io/projects/4160)

```bash
$ npm install nzb-grabber-js
```

Pass an NZB file buffer which will be parsed and all files and their chunks downloaded. Chunks arrive in order so you can append them to an existing file. When all files are downloaded `done` is set.

```coffee-script
NzbGrabber = require 'nzb-grabber-js'

client = new NzbGrabber
    'host': 'news.usenetserver.com'
    'port': 119,
    'user': 'username'
    'pass': 'password'
    'conn': 4

client.grab nzbFile, (err, filename, chunk, done) ->
    fs.appendFile './downloads/' + filename, chunk, (err) ->
        console.log 'All files downloaded' if done
```

Have a look into `./example/watch.coffee`.

[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/radekstepan/nzb-grabber-js/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

