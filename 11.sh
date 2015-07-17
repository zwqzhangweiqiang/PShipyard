export PYTHONPATH=/usr/lib/python2.7/
uwsgi --pythonpath /usr/lib/python2.7 --pyimport site --http-socket 0.0.0.0:5000 -p 4 -b 32768 -T --master --max-requests 5000 -H /usr/ --static-map /static=/root/shipyard/static --static-map /static=/usr/lib/python2.7/site-packages/django/contrib/admin/static --module wsgi:application
