package configs

import (
	"github.com/statping/statping/database"
	"github.com/statping/statping/notifiers"
	"github.com/statping/statping/types/checkins"
	"github.com/statping/statping/types/core"
	"github.com/statping/statping/types/failures"
	"github.com/statping/statping/types/groups"
	"github.com/statping/statping/types/hits"
	"github.com/statping/statping/types/incidents"
	"github.com/statping/statping/types/messages"
	"github.com/statping/statping/types/services"
	"github.com/statping/statping/types/users"
	"github.com/statping/statping/utils"
	"gopkg.in/yaml.v2"
	"os"
)

type SamplerFunc func() error

type Sampler interface {
	Samples() []database.DbObject
}

func TriggerSamples() error {
	return createSamples(
		core.Samples,
		//users.Samples,
		messages.Samples,
		services.Samples,
		checkins.Samples,
		checkins.SamplesChkHits,
		failures.Samples,
		groups.Samples,
		hits.Samples,
		incidents.Samples,
		incidents.SamplesUpdates,
	)
}

func createSamples(sm ...SamplerFunc) error {
	for _, v := range sm {
		if err := v(); err != nil {
			return err
		}
	}
	return nil
}

// Migrate function
func (d *DbConfig) Update() error {
	var err error
	config, err := os.Create(utils.Directory + "/config.yml")
	if err != nil {
		return err
	}
	defer config.Close()

	data, err := yaml.Marshal(d)
	if err != nil {
		log.Errorln(err)
		return err
	}
	config.WriteString(string(data))
	return nil
}

// Save will initially create the config.yml file
func (d *DbConfig) Delete() error {
	return os.Remove(d.filename)
}

// DropDatabase will DROP each table Statping created
func (d *DbConfig) DropDatabase() error {
	var DbModels = []interface{}{&services.Service{}, &users.User{}, &hits.Hit{}, &failures.Failure{}, &messages.Message{}, &groups.Group{}, &checkins.Checkin{}, &checkins.CheckinHit{}, &notifiers.Notification{}, &incidents.Incident{}, &incidents.IncidentUpdate{}}
	log.Infoln("Dropping Database Tables...")
	for _, t := range DbModels {
		if err := d.Db.DropTableIfExists(t); err != nil {
			return err.Error()
		}
		log.Infof("Dropped table: %T\n", t)
	}
	return nil
}

func (d *DbConfig) Close() {
	if d.Db != nil {
		d.Db.Close()
	}
}

// CreateDatabase will CREATE TABLES for each of the Statping elements
func (d *DbConfig) CreateDatabase() error {
	var err error

	var DbModels = []interface{}{&services.Service{}, &users.User{}, &hits.Hit{}, &failures.Failure{}, &messages.Message{}, &groups.Group{}, &checkins.Checkin{}, &checkins.CheckinHit{}, &notifiers.Notification{}, &incidents.Incident{}, &incidents.IncidentUpdate{}}

	log.Infoln("Creating Database Tables...")
	for _, table := range DbModels {
		if err := d.Db.CreateTable(table); err.Error() != nil {
			return err.Error()
		}
	}
	if err := d.Db.Table("core").CreateTable(&core.Core{}); err.Error() != nil {
		return err.Error()
	}
	log.Infoln("Statping Database Created")

	return err
}
