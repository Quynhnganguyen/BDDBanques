drop table if exists t_compte cascade;
drop table if exists t_compte_vue cascade;
drop table if exists t_operation cascade;
drop table if exists t_virement_permanent cascade;
drop table if exists t_virement_unique cascade;
drop table if exists t_retrait cascade;
drop table if exists t_depot cascade;
drop table if exists t_mandataire cascade;
DROP TABLE IF EXISTS t_client cascade;
DROP TABLE IF EXISTS t_personne cascade;
DROP TABLE IF EXISTS t_association cascade;
DROP TABLE IF EXISTS t_entreprise cascade;
drop table if exists t_moyen_paiement cascade;
drop table if exists t_avantages cascade;
drop table if exists t_CB cascade;
drop table if exists t_cheque cascade;
drop table if exists t_date;
drop table if exists t_releve_compte cascade;
drop view if exists v_releve_compte cascade;

create table t_date (
	annee int primary key,
	trimestre int,
	mois int,
	semaine int,
	jour int
);
insert into t_date values(2011,3,8,38,15);

CREATE TABLE t_client (
	ID_client serial PRIMARY KEY,
	nom varchar(40),
	adresse varchar(100),
	tel varchar(13)
);


CREATE TABLE t_personne (
	ID_personne int PRIMARY KEY references t_client(ID_client),
	prenom varchar(40),
	sexe char
);

CREATE TABLE t_association (
	ID_ass int PRIMARY KEY references t_client(ID_client)
);

CREATE TABLE t_entreprise (
	ID_entr int PRIMARY KEY references t_client(ID_client)
);

create table t_compte
(
	IBAN int,
	BIC varchar(20),
	actif boolean default true,
	solde float default 0,
	decouvert_autorise int default 0,
	taux_decouvert float default 0, 
	depassement_decouvert int default 0,
	taux_agios float default 0,
	primary key (IBAN,BIC)
);
insert into t_compte values(0,'Banque',true, 1000000,0,0,0,0);

create table t_compte_vue
(
	IBAN int,
	BIC varchar(20),
	proprietaire int references t_client(id_client),
	primary key (IBAN,BIC),
	foreign key (IBAN,BIC) references t_compte(IBAN,BIC)
);

create table t_operation
(
	ID serial primary key,
	intitule varchar(40),
	cout float,
	montant float,
	date_op date,
	debit_IBAN int,
	debit_BIC varchar(20),
	credit_IBAN int,
	credit_BIC varchar(20),
	foreign key (debit_IBAN,debit_BIC) references t_compte(IBAN,BIC),
	foreign key (credit_IBAN,credit_BIC) references t_compte(IBAN,BIC)
);

create table t_virement_permanent
(
	ID int primary key references t_operation(ID),
	periodicite char
);

create table t_retrait
(
	ID int primary key references t_operation(ID)
);

create table t_depot
(
	ID int primary key references t_operation(ID)
);

create table t_virement_unique
(
	ID int primary key references t_operation(ID)
);


create table t_mandataire
(
	personne_id int references t_personne(id_personne),
	compte_IBAN int,
	compte_BIC varchar(20),
	primary key (personne_ID,compte_IBAN,compte_BIC),
	foreign key (compte_IBAN,compte_BIC) references t_compte(IBAN,BIC)
);

create table t_moyen_paiement (
	id serial primary key,
	nom varchar(40),
	prix float
);
insert into t_moyen_paiement(nom,prix) values('operation interne',0);
insert into t_moyen_paiement(nom,prix) values('mastercard',10);
insert into t_moyen_paiement(nom,prix) values('chequier',3);
insert into t_moyen_paiement(nom,prix) values('carte jeune',2.5);

create table t_avantages (
	moyen_paiement_id int references t_moyen_paiement(id),
	compte_IBAN int,
	compte_BIC varchar(20),
	primary key (moyen_paiement_ID,compte_IBAN,compte_BIC),
	foreign key (compte_IBAN,compte_BIC) references t_compte(IBAN,BIC)
);

create table t_CB (
	id int primary key references t_moyen_paiement(id)
);

insert into t_CB values(3);
insert into t_CB values(2);

create table t_cheque (
	id int primary key references t_moyen_paiement(id)
);

insert into t_cheque values(4);

create table t_releve_compte (
	iban int,
	bic varchar(20),
	date_op date,
	operation varchar(40),
	montant float,
	cout float,
	primary key(iban, bic),
	foreign key (IBAN,BIC) references t_compte(IBAN,BIC)
);

create view v_releve_compte as
select iban, bic, date_op, operation, montant, cout from t_releve_compte where
iban in 
(select iban from t_compte_vue t where cast(proprietaire as varchar)=current_user or current_user in (select cast(personne_id as varchar) from t_mandataire where compte_iban = t.iban and compte_bic = t.bic))
and bic in
(select bic from t_compte_vue t where cast(proprietaire as varchar)=current_user or current_user in (select cast(personne_id as varchar) from t_mandataire where compte_iban = t.iban and compte_bic = t.bic))
order by iban, bic;

