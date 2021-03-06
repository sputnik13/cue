# Copyright 2014 Hewlett-Packard Development Company, L.P.
#
# Authors: Davide Agnello <davide.agnello@hp.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Copyright [2014] Hewlett-Packard Development Company, L.P.
# limitations under the License.

from cue.db import api as db_api
from cue.objects import base
from cue.objects import utils as obj_utils


class Endpoint(base.CueObject):

    dbapi = db_api.get_instance()

    fields = {
        'id': obj_utils.str_or_none,
        'node_id': obj_utils.str_or_none,
        'uri': obj_utils.str_or_none,
        'type': obj_utils.str_or_none,
    }

    @staticmethod
    def _from_db_object(cluster, db_cluster):
        """Convert a database object to a universal endpoint object."""
        for field in cluster.fields:
            cluster[field] = db_cluster[field]
        return cluster

    def create(self, context):
        """Creates a new endpoint.

        :param context: The request context

        """
        endpoint_changes = self.obj_get_changes()

        db_endpoint = self.dbapi.create_endpoint(context, endpoint_changes)

        self._from_db_object(self, db_endpoint)

    @classmethod
    def update_by_node_id(cls, context, node_id, endpoint_changes):
        """Updates a database endpoint object.

        :param context: The request context
        :param node_id: The node id
        :param endpoint_changes: dictionary of endpoint changes
        """
        cls.dbapi.update_endpoints_by_node_id(context, endpoint_changes,
                                              node_id)

    @classmethod
    def get_endpoints_by_node_id(cls, context, node_id):
        """Returns a list of Endpoint objects for specified node.

        :param node_id: UUID of the node.
        :returns: a list of :class:'Endpoint' object.

        """
        db_endpoints = cls.dbapi.get_endpoints_in_node(context, node_id)

        return [Endpoint._from_db_object(Endpoint(), obj) for obj in db_endpoints]