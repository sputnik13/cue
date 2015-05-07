# Copyright 2014 OpenStack Foundation
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import json
import logging
import urllib

from tempest_lib.common import rest_client

from tests.integration.common.client import BaseMessageQueueClient

LOG = logging.getLogger(__name__)


class MessageQueueClustersClient(BaseMessageQueueClient):
    """This class is used for creating a Cue Cluster client.

    It contains all the CRUD requests for Cue Clusters.
    """

    def list_clusters(self, params=None):
        """List all clusters

        :param params: Optional parameters for listing cluster
        """
        url = 'clusters'
        if params:
            url += '?%s' % urllib.urlencode(params)

        resp, body = self.get(url)
        self.expected_success(200, resp.status)
        return rest_client.ResponseBodyData(resp, body)

    def get_cluster_details(self, cluster_id):
        """Get a cluster

        :param cluster_id: The ID of the cluster to get
        """
        resp, body = self.get("clusters/%s" % str(cluster_id))
        self.expected_success(200, resp.status)
        return rest_client.ResponseBody(resp, self._parse_resp(body))

    def create_cluster(self, name, flavor, network_id):
        """Create a new cluster with one node

        :param name: The name of the cluster
        :param flavor: The flavor of the cluster
        :param network_id: The network_id to associate the cluster
        """
        post_body = {
            'name': name,
            'size': 1,
            "flavor": flavor,
            'volume_size': 100,
            "network_id": network_id,
        }

        post_body = post_body
        post_body = json.dumps(post_body)

        resp, body = self.post('clusters', post_body)
        return rest_client.ResponseBody(resp, self._parse_resp(body))

    def delete_cluster(self, cluster_id):
        """Delete a cluster

        :param cluster_id: The ID of the cluster to delete
        """
        resp, body = self.delete("clusters/%s" % str(cluster_id))
        self.expected_success(202, resp.status)
        return rest_client.ResponseBody(resp, body)