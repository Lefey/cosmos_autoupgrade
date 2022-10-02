# Cosmos forks autoupgrade script
Script for catching info from upgrade proposals and make upgrade at needeed height

Change params, add to crontab.
```
*/5 * * * * bash $HOME/upgrade.sh >> $HOME/upgrade.log 2>&1
```
Make shure that you make symbolic link from curent chain binary to system binary folder, for example
```
ln -s /root/.gaiad/current/gaiad /usr/local/bin/gaiad
```
and in service file you specified it
ExecStart=/usr/local/bin/chaind start
When upgrade, script will delete /root/.gaiad/current
and then make symbolic link from new binary folder to current folder.
For example. script will do
```
rm -rf /root/.gaiad/current
ln -s /root/.gaiad/new_ver_1.1 /root/.gaiad/current
```
