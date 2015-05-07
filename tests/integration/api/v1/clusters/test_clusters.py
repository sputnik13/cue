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

"""
Tests for the API /cluster/ controller methods.
"""

import logging

import tempest_lib.base
from tempest_lib.common.utils import data_utils

from tests.integration.api.v1.clients import clusters_client
from tests.integration.common import config


CONF = config.get_config()
LOG = logging.getLogger(__name__)


class ClusterTest(tempest_lib.base.BaseTestCase):
    """Cluster integration tests for Cue."""

    @classmethod
    def setUpClass(cls):
        super(ClusterTest, cls).setUpClass()
        cls.client = clusters_client.MessageQueueClustersClient()

    def setUp(self):
        super(ClusterTest, self).setUp()
        self.cluster = self._create_cluster()

    def tearDown(self):
        super(ClusterTest, self).tearDown()
        self.client.delete_cluster(self.cluster['id'])

    def _create_cluster(self):
        name = data_utils.rand_name(ClusterTest.__name__ + "-cluster")
        network_id = [self.client.private_network['id']]
        flavor = CONF.message_queue.flavor
        return self.client.create_cluster(name, flavor, network_id)

    def test_list_clusters(self):
        clusters = self.client.list_clusters()
        self.assertIn('id', clusters.data)
        self.assertIn('status', clusters.data)

    def test_get_cluster(self):
        cluster_resp = self.client.get_cluster_details(self.cluster['id'])
        self.assertEqual(self.cluster['id'], cluster_resp['id'])
        self.assertEqual(self.cluster['name'], cluster_resp['name'])