/*
Copyright 2017 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package validation

import (
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/openshift/cluster-operator/pkg/apis/clusteroperator"
)

// getValidClusterVersion gets a cluster version that passes all validity checks.
func getValidClusterVersion() *clusteroperator.ClusterVersion {
	masterAMIID := "masterAMI_ID"
	return &clusteroperator.ClusterVersion{
		ObjectMeta: metav1.ObjectMeta{
			Name: "test-cluster-version",
		},
		Spec: clusteroperator.ClusterVersionSpec{
			ImageFormat: "openshift/origin-${component}:${version}",
			YumRepositories: []clusteroperator.YumRepository{
				{
					ID:       "testrepo",
					Name:     "a testing repo",
					BaseURL:  "http://example.com/nobodycares/",
					Enabled:  1,
					GPGCheck: 1,
					GPGKey:   "http://example.com/notreal.gpg",
				},
			},
			VMImages: clusteroperator.VMImages{
				AWSImages: &clusteroperator.AWSVMImages{
					RegionAMIs: []clusteroperator.AWSRegionAMIs{
						{
							Region:    "us-east-1",
							AMI:       "computeAMI_ID",
							MasterAMI: &masterAMIID,
						},
					},
				},
			},
			DeploymentType: clusteroperator.ClusterDeploymentTypeOrigin,
			Version:        "3.7.0",
		},
	}
}

// TestValidateClusterVersion tests the ValidateClusterVersion function.
func TestValidateClusterVersion(t *testing.T) {
	cases := []struct {
		name           string
		clusterVersion *clusteroperator.ClusterVersion
		valid          bool
	}{
		{
			name:           "valid",
			clusterVersion: getValidClusterVersion(),
			valid:          true,
		},
		{
			name: "missing image format",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.ImageFormat = ""
				return c
			}(),
			valid: false,
		},
		{
			name: "invalid yum repo missing id",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.YumRepositories[0].ID = ""
				return c
			}(),
			valid: false,
		},
		{
			name: "invalid yum repo missing name",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.YumRepositories[0].Name = ""
				return c
			}(),
			valid: false,
		},
		{
			name: "invalid yum repo missing baseurl",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.YumRepositories[0].BaseURL = ""
				return c
			}(),
			valid: false,
		},
		{
			name: "invalid yum repo enabled int",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.YumRepositories[0].Enabled = 2
				return c
			}(),
			valid: false,
		},
		{
			name: "invalid yum repo gpgcheck int",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.YumRepositories[0].GPGCheck = -1
				return c
			}(),
			valid: false,
		},
		{
			name: "missing VM images",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.VMImages = clusteroperator.VMImages{}
				return c
			}(),
			valid: false,
		},
		{
			// This test is only valid until we start supporting mutliple clusters, in which case
			// it should instead verify at least one cloud provider has images defined:
			name: "missing AWS VM images",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.VMImages.AWSImages = nil
				return c
			}(),
			valid: false,
		},
		{
			name: "no region AMIs",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.VMImages.AWSImages.RegionAMIs = []clusteroperator.AWSRegionAMIs{}
				return c
			}(),
			valid: false,
		},
		{
			name: "missing AMI region",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.VMImages.AWSImages.RegionAMIs[0].Region = ""
				return c
			}(),
			valid: false,
		},
		{
			name: "missing AMI ID",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.VMImages.AWSImages.RegionAMIs[0].AMI = ""
				return c
			}(),
			valid: false,
		},
		{
			name: "empty master AMI ID",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				var emptyStr string
				c.Spec.VMImages.AWSImages.RegionAMIs[0].MasterAMI = &emptyStr
				return c
			}(),
			valid: false,
		},
		{
			name: "duplicate region AMIs",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.VMImages.AWSImages.RegionAMIs = append(c.Spec.VMImages.AWSImages.RegionAMIs,
					clusteroperator.AWSRegionAMIs{Region: "us-east-1", AMI: "fakecompute"})
				return c
			}(),
			valid: false,
		},
		{
			name: "missing deployment type",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.DeploymentType = ""
				return c
			}(),
			valid: false,
		},
		{
			name: "invalid deployment type",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.DeploymentType = "badtype"
				return c
			}(),
			valid: false,
		},
		{
			name: "missing version",
			clusterVersion: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.Version = ""
				return c
			}(),
			valid: false,
		},
	}

	for _, tc := range cases {
		errs := ValidateClusterVersion(tc.clusterVersion)
		if len(errs) != 0 && tc.valid {
			t.Errorf("%v: unexpected error: %v", tc.name, errs)
			continue
		} else if len(errs) == 0 && !tc.valid {
			t.Errorf("%v: unexpected success", tc.name)
		}
	}
}

// TestValidateClusterVersionUpdate tests the ValidateClusterVersionUpdate function. Updates are not
// supported at this time, so any modification should return an error.
func TestValidateClusterVersionUpdate(t *testing.T) {
	cases := []struct {
		name  string
		old   *clusteroperator.ClusterVersion
		new   *clusteroperator.ClusterVersion
		valid bool
	}{
		{
			name:  "valid",
			old:   getValidClusterVersion(),
			new:   getValidClusterVersion(),
			valid: true,
		},
		{
			name: "modified image format",
			old:  getValidClusterVersion(),
			new: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.ImageFormat = "abc"
				return c
			}(),
			valid: false,
		},
		{
			name: "modified yum repo",
			old:  getValidClusterVersion(),
			new: func() *clusteroperator.ClusterVersion {
				c := getValidClusterVersion()
				c.Spec.YumRepositories[0].BaseURL = "http://new.com"
				return c
			}(),
			valid: false,
		},
	}

	for _, tc := range cases {
		errs := ValidateClusterVersionUpdate(tc.new, tc.old)
		if len(errs) != 0 && tc.valid {
			t.Errorf("%v: unexpected error: %v", tc.name, errs)
			continue
		} else if len(errs) == 0 && !tc.valid {
			t.Errorf("%v: unexpected success", tc.name)
		}
	}
}
